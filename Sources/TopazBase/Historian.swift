//
//  Historian.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//
import Foundation

/// `Historian` stores a version number along with each client's data.
/// Clients can use this to orchestrate changes in their history data format.
public typealias HistoryVersion = UInt32

extension HistoryVersion {
    /// All client history data starts with a version of zero
    static public var FIRST_VERSION: HistoryVersion { return 0 }
}

/// Clients access history via regular `Codable` protocols using JSON encoders
/// and decoders passed in from the `Historian`.  Data integrity is added below
/// this level.
///
/// World restore has two phases. First each client restores their own data from
/// the history.  Then when all are done the `Historical.restoreComplete()` method
/// is called to let clients reestablish relationships (eg. reestablish timers).
/// [If we run into dependency problems here then will just have to get back into
/// those weeds...]
///
/// `Historical` offers a versioning story. Clients are free to use this or do their
/// own thing against their own datastore. The `Historical.historyVersion` and
/// `Historical.convert(...)` fields have safe default implementations.
public protocol Historical {
    /// Key to save this client's history under
    var historyName: String { get }

    /// Save the client's state using the given `JSONEncoder`
    func saveHistory(using encoder: JSONEncoder) -> Data

    /// Restore the client's state using the `JSONDecoder`.
    /// `data` is guaranteed to be at version `historyVersion`.
    func restoreHistory(from data: Data, using decoder: JSONDecoder) throws

    /// Called when all clients have been decoded OK.  Use this to eg. reestablish
    /// communicationswith other clients based on now-shared state.
    func restoreComplete()

    /// What version of history does the client expect in `restore(...)`?
    var historyVersion: HistoryVersion { get }

    /// Convert client history data written at `atVersion` to the current `historyVersion`.
    /// This is persisted replacing the old one, then (probably) passed to `restore(...)`.
    func convert(from: Data, atVersion: HistoryVersion,
                 usingDecoder decoder: JSONDecoder, usingEncoder encoder: JSONEncoder) throws -> Data
}

/// Default implementations for `Historical`
extension Historical {
    /// By default do nothing when all clients have restored their state
    public func restoreComplete() {}

    /// By default return `HistoryVersion.FIRST_VERSION`
    public var historyVersion: HistoryVersion { return .FIRST_VERSION }

    /// By default fail if asked to convert versions - data must be corrupt/from the future.
    public func convert(from: Data, atVersion: HistoryVersion,
                        usingDecoder decoder: JSONDecoder, usingEncoder encoder: JSONEncoder) throws -> Data {
        throw RestoreError("HistoryStorable.convert unimplemented, can't convert from \(atVersion) to \(historyVersion)")
    }
}

extension Historical where Self: DebugDumpable {
    /// Use the debugName for the historyName when possible
    public var historyName: String { return debugName }
}

/// The data stored by `Historian` per client per turn
public struct HistoricalTurnData: Codable {
    /// Encoded client data
    public let turnData: Data
    /// `HistoryVersion` of `turnData`
    public let version: HistoryVersion
}

/// Persistence services for `Historian`.  Typically produced by a `HistoryStore` on which
/// `Historian` has no direct dependency.
public protocol HistoryAccess: CustomStringConvertible {
    /// Create or update the data for `turn`.
    func setDataForTurn(_ turn: Turn, data: [String : HistoricalTurnData]) throws

    /// Retrieve the data for `turn`.
    func loadDataForTurn(_ turn: Turn) throws -> [String : HistoricalTurnData]

    /// The most recent `Turn` stored, or nil if the `History` is empty
    var mostRecentTurn: Turn? { get }

    /// Mark the history as 'active' which, eg., should stop it from being deleted
    var active: Bool { get set }
}

/// `Historian` records changes to world state as turns progress.  It also deals with
/// restoring the world to match a previously recorded state.
///
/// Clients that want to be part of history register a `Historical` instance during
/// initialization.
///
/// Restoration works by pausing turns, overwriting existing state, allowing
/// components to reestablish relationships, and then resuming turns.  See `Historical`.
final public class Historian: DebugDumpable, Logger {
    /// Logger
    public let logMessageHandler: LogMessage.Handler

    /// DebugDumpable
    public let debugName = "Historian"
    public var description: String {
        return "\(clients.count) clients, history is \(historyAccess?.description ?? "(nil)")"
    }

    /// The current world history.  See `Services.setNewHistory(...)`.
    public var historyAccess: HistoryAccess? {
        willSet {
            historyAccess?.active = false
            historyAccess.map { self.log(.info, "Deactivating history \($0)") }
        }
        didSet {
            historyAccess?.active = true
            historyAccess.map { self.log(.info, "Activating history \($0)") }
        }
    }

    /// Clients registered for save/restore
    private var clients: [String : Historical]

    /// Subscribe to be part of history saving + restoration
    public func register(historical client: Historical) {
        let name = client.historyName
        guard clients[name] == nil else {
            log(.error, "Multiple clients registering with history name \(name)")
            fatalError()
        }
        clients[name] = client
    }

    /// Customized json encode/decode
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    /// Create a new Historian
    public init(debugDumper: DebugDumper) {
        self.logMessageHandler = debugDumper.logMessageHandler
        self.historyAccess = nil
        self.clients = [:]
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        debugDumper.register(debugDumpable: self)
    }

    /// Save history.  Usually called by `TurnSource` after each turn completes with the ID of the
    /// `Turn` that has just completed.  This happens often so logging is filtered.
    public func save(turn: Turn) {
        DispatchQueue.checkTurnQueue(self)
        guard let historyAccess = historyAccess else {
            log(.error, "Call to save history but history access not configured")
            fatalError()
        }

        log(.debugHistory, "Start saving data for turn \(turn)")

        var data: [String : HistoricalTurnData] = [:]

        clients.values.forEach { historical in
            log(.debugHistory, "Collecting data for client \(historical.historyName)")
            let turnData = historical.saveHistory(using: jsonEncoder)
            let version  = historical.historyVersion
            data[historical.historyName] = HistoricalTurnData(turnData: turnData, version: version)
            log(.debugHistory, "Collected data at version \(version)")
        }

        do {
            log(.debugHistory, "Writing turn data for turn \(turn)")
            try historyAccess.setDataForTurn(turn, data: data)
        } catch {
            log(.warning, "Failed to save turn data: \(error).  Pressing on.")
        }
        log(.debugHistory, "End saving data for turn \(turn)")
    }

    /// Restore all clients' turn data.  This is a bit of a dance.  Happens rarely, log @info.
    public func restoreAtTurn(_ turn: Turn) throws {
        DispatchQueue.checkTurnQueue(self)
        guard let historyAccess = historyAccess else {
            log(.error, "Call to restore history but history access not configured")
            fatalError()
        }

        log(.info, "Start restoring data for turn \(turn)")

        // 1 - get data from store
        var turnData = try historyAccess.loadDataForTurn(turn)
        var turnDataChanged = false

        // 2 - fan restored data out to clients
        try clients.values.forEach { historical in
            let historyName = historical.historyName
            guard var historicalTurnData = turnData[historyName] else {
                let missingMsg = "Historical \(historyName), nothing found in turn data - cancel restore"
                log(.warning, missingMsg)
                throw RestoreError(missingMsg)
            }

            let dataVersion = historicalTurnData.version
            let liveVersion = historical.historyVersion

            guard dataVersion <= liveVersion else {
                let versionMsg = "Historical \(historyName), turn data version \(dataVersion) incompatible with " +
                                 "declared version \(liveVersion) - cancel restore"
                log(.warning, versionMsg)
                throw RestoreError(versionMsg)
            }

            if dataVersion < liveVersion {
                log(.info, "Historical \(historyName), turn data version \(dataVersion) needs converting to " +
                           "declared version \(liveVersion)")
                let newVersionData = try historical.convert(from: historicalTurnData.turnData,
                                                            atVersion: historicalTurnData.version,
                                                            usingDecoder: jsonDecoder,
                                                            usingEncoder: jsonEncoder)
                log(.info, "Historical \(historyName) turn data version conversion done")
                historicalTurnData = HistoricalTurnData(turnData: newVersionData, version: historical.historyVersion)
                turnData[historyName] = historicalTurnData
                turnDataChanged = true
            }

            log(.info, "Historical \(historyName) restore")
            try historical.restoreHistory(from: historicalTurnData.turnData, using: jsonDecoder)
            log(.debug, "Historical \(historyName) restore done")
        }

        // 3 - if any clients did an upgrade, re-save the data
        if turnDataChanged {
            log(.info, "Re-writing turn data for turn \(turn)")
            try historyAccess.setDataForTurn(turn, data: turnData)
            log(.debug, "Re-write done")
        }

        log(.info, "Component data restore done, sending restore-complete")

        // 4 - fan restore-complete out to clients
        clients.values.forEach { historical in
            log(.debug, "Historical \(historical.historyName) sending restore-complete")
            historical.restoreComplete()
            log(.debug, "Historical \(historical.historyName) restore-complete done")
        }

        log(.info, "End restoring data for turn \(turn)")
    }
}
