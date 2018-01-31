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

    /// Change the client's state to be ready for the initial turn of a new world.
    func restoreInitialHistory()

    /// Save the client's state using the given `JSONEncoder`
    func saveHistory(using encoder: JSONEncoder) -> Data

    /// Restore the client's state using the `JSONDecoder`.
    /// `data` is guaranteed to be at version `historyVersion`.
    func restoreHistory(from data: Data, using decoder: JSONDecoder) throws

    /// Set up the client's state when a restore happens but no history data
    /// was present for the client.  Client should throw if this is not expected;
    /// it happens when a new client is introduced to an existing world.
    func restoreHistoryNoDataFound() throws

    /// Called when all clients have been decoded OK.  Use this to eg. reestablish
    /// communications with other clients based on now-shared state.
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
    /// By default fail when no data found
    public func restoreHistoryNoDataFound() throws {
        throw TopazError("Historical.restoreHistoryNoDataFound unimplemented, can't handle missing data")
    }

    /// By default do nothing when all clients have restored their state
    public func restoreComplete() {}

    /// By default return `HistoryVersion.FIRST_VERSION`
    public var historyVersion: HistoryVersion { return .FIRST_VERSION }

    /// By default fail if asked to convert versions - means client has set historyVersion but not
    /// implemented this method to deal with a conversion.
    public func convert(from: Data, atVersion: HistoryVersion,
                        usingDecoder decoder: JSONDecoder, usingEncoder encoder: JSONEncoder) throws -> Data {
        throw TopazError("Historical.convert unimplemented, can't convert from \(atVersion) to \(historyVersion)")
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

    public init(turnData: Data, version: HistoryVersion) {
        self.turnData = turnData
        self.version = version
    }
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
        return "\(clients.count) clients, history is \(String(describing: historyAccess))"
    }

    /// The current world history, nil during startup
    public private(set) var historyAccess: HistoryAccess?

    /// Clients registered for save/restore
    private var clients: [String : Historical]

    /// Subscribe to be part of history saving + restoration
    public func register(historical client: Historical) {
        guard historyAccess == nil else {
            // Coding error
            fatal("Attempt to add history client after world has been restored")
        }
        let name = client.historyName
        guard clients[name] == nil else {
            fatal("Multiple clients registering with history name \(name)")
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
        guard historyAccess != nil else {
            fatal("Call to save history but history access not configured")
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

        log(.debugHistory, "Writing turn data for turn \(turn)")
        saveDataForTurn(turn, data: data)
        log(.debugHistory, "End saving data for turn \(turn)")
    }

    /// Helper to save turn data, suppressing propagation of any error
    private func saveDataForTurn(_ turn: Turn, data: [String : HistoricalTurnData]) {
        do {
            try historyAccess!.setDataForTurn(turn, data: data)
        } catch {
            log(.warning, "Failed to save turn data: \(error).  Pressing on.")
        }
    }

    /// Change (set) the history storage and sync the world to its contents
    public func setNewHistory(historyAccess: HistoryAccess) throws {
        if var oldAccess = self.historyAccess {
            oldAccess.active = false
            log(.info, "Deactivating history \(oldAccess)")
        }
        self.historyAccess = historyAccess
        self.historyAccess?.active = true
        log(.info, "Activating history \(historyAccess)")

        if let latestTurn = historyAccess.mostRecentTurn {
            log(.info, "New history not empty, restoring from it")
            try restoreAtTurn(latestTurn)
        } else {
            log(.info, "New history is empty, resetting world")
            restoreAtInitialTurn()
        }
    }

    /// Restore all clients' turn data.  This is a bit of a dance.  Happens rarely, log @info.
    public func restoreAtTurn(_ turn: Turn) throws {
        DispatchQueue.checkTurnQueue(self)
        guard let historyAccess = historyAccess else {
            try throwError("Historian.restoreAtTurn - historyaccess not configured")
        }

        log(.info, "Start restoring data for turn \(turn)")

        // 1 - get data from store
        var turnData = try historyAccess.loadDataForTurn(turn)
        var turnDataChanged = false

        // 2 - fan restored data out to clients
        try clients.forEach { historyName, historical in
            guard var historicalTurnData = turnData[historyName] else {
                log(.info, "Historical \(historyName) no data found")
                try historical.restoreHistoryNoDataFound()
                log(.debug, "Historical \(historyName) no data found done")
                return // next client
            }

            let dataVersion = historicalTurnData.version
            let liveVersion = historical.historyVersion

            guard dataVersion <= liveVersion else {
                try throwError("Historical \(historyName), turn data version \(dataVersion) incompatible with " +
                               "declared version \(liveVersion) - cancel restore")
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
            saveDataForTurn(turn, data: turnData)
            log(.debug, "Re-write done")
        }

        log(.info, "Client data restore done, sending restore-complete")

        // 4 - fan restore-complete out to clients
        sendAllClientsRestoreComplete()

        log(.info, "End restoring data for turn \(turn)")
    }

    /// Helper, send the restore-complete to all clients
    private func sendAllClientsRestoreComplete() {
        clients.forEach { historyName, historical in
            log(.debug, "Historical \(historyName) restore-complete")
            historical.restoreComplete()
            log(.debug, "Historical \(historyName) restore-complete done")
        }
    }

    /// Coordinate all clients to reset to their initial state.
    private func restoreAtInitialTurn() {
        DispatchQueue.checkTurnQueue(self)

        log(.info, "Start restoring data for initial turn")

        clients.forEach { historyName, historical in
            log(.info, "Historical \(historyName) initial restore")
            historical.restoreInitialHistory()
            log(.debug, "Historical \(historyName) initial restore done")
        }

        log(.info, "Client reset done, sending restore-complete")

        sendAllClientsRestoreComplete()

        log(.info, "End restoring data for initial turn")
    }
}
