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

/// Clients access history using regular `Codable` classes.  They implement `Encodable`
/// to save data but restore is done via a `Historical.restore(from:)` method instead of the `Decodable`
/// constructor.
///
/// World restore has two phases.  First each client restores their own data from the history.
/// Then when all are done the `Historical.restoreComplete` method is called to let clients
/// reestablish relationships.  If we run into dependency problems here then will have to get back
/// into those weeds...
///
/// `Historical` offers a versioning story; clients are free to use this or do their own thing against
/// their own datastore.  The `Historical.historyVersion` and `Historical.convert(...)`
/// fields have safe default implementations.
public protocol Historical {
    /// Save the client's state using the given `JSONEncoder`
    func saveHistory(using encoder: JSONEncoder) -> Data

    /// Restore the client's state using the `JSONDecoder`.  The data is guaranteed to be at version `historyVersion`.
    func restoreHistory(from data: Data, using decoder: JSONDecoder) throws

    /// Called when all clients have been decoded OK.  Use this to eg. reestablish communications
    /// with other clients based on now-shared state.
    func restoreComplete()

    /// What version of history does the client expect in `restore(...)`?
    var historyVersion: HistoryVersion { get }

    /// Convert client history data written at `atVersion` to the current `historyVersion`.  This
    /// will be persisted replacing the old one, then (probably) passed to `restore(...)`.
    func convert(from: Data, atVersion: HistoryVersion,
                 usingDecoder decoder: JSONDecoder, usingEncoder encoder: JSONEncoder) throws -> Data
}

/// Default implementations for `Historical`
extension Historical {
    /// By default do nothing when all clients have restored their state
    public func restoreComplete() {}

    /// By default return `HistoryVersion.FIRST_VERSION`
    public var historyVersion: HistoryVersion { return .FIRST_VERSION }

    /// By default fail if asked to convert versions
    public func convert(from: Data, atVersion: HistoryVersion,
                        usingDecoder decoder: JSONDecoder, usingEncoder encoder: JSONEncoder) throws -> Data {
        throw RestoreError(details: "HistoryStorable.convert unimplemented, can't convert from \(atVersion) to \(historyVersion)")
    }
}

/// The data stored by `Historian` per client per turn
public struct HistoricalTurnData: Codable {
    /// Encoded client data
    public let turnData: Data
    /// `HistoryVersion` of `turnData`
    public let version: HistoryVersion
}

/// Persistence services for `Historian`.  Typically produced by a `HistoryStore` on which `Historian`
/// has no direct dependency.
public protocol HistoryAccess {
    /// Create or update the data for the given `Turn`
    func setDataForTurn(_ turn: Turn, data: [String : HistoricalTurnData]) throws

    /// Retrieve the data for the given `Turn`
    func loadDataForTurn(_ turn: Turn) throws -> [String : HistoricalTurnData]

    /// Retrieves the data for the most recent `Turn`, or nil if the `History` is empty
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
final public class Historian: Logger {
    /// Logger
    public var logMessageHandler: LogMessage.Handler
    public let logPrefix = "Historian"

    /// The current world history.  See `Services.setNewHistory(...)`.
    public var historyAccess: HistoryAccess? {
        willSet {
            historyAccess?.active = false
        }
        didSet {
            historyAccess?.active = true
        }
    }

    private var clients: [String : Historical]

    /// Subscribe to be part of history saving + restoration
    public func register(client: Historical, withId id: String) {
        guard clients[id] == nil else {
            log(.error, "Multiple clients registering with id \(id)")
            fatalError()
        }
        clients[id] = client
    }

    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    /// Create a new Historian
    public init(logMessageHandler: @escaping LogMessage.Handler) {
        self.logMessageHandler = logMessageHandler
        self.historyAccess = nil
        self.clients = [:]
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    /// Save history.  Usually called by `TurnSource` after each turn completes with the ID of the
    /// `Turn` that has just completed.
    public func save(turn: Turn) {
        DispatchQueue.checkTurnQueue(self)
        guard let historyAccess = historyAccess else {
            log(.error, "Call to save history but history access not configured")
            fatalError()
        }

        var data: [String : HistoricalTurnData] = [:]

        clients.forEach { name, historical in
            let turnData = historical.saveHistory(using: jsonEncoder)
            data[name] = HistoricalTurnData(turnData: turnData, version: historical.historyVersion)
        }

        do {
            try historyAccess.setDataForTurn(turn, data: data)
        } catch {
            log(.warning, "Failed to save turn data: \(error).  Pressing on.")
        }
    }

    /// Restore all clients' turn data.  This is a bit of a dance.
    public func restoreAtTurn(_ turn: Turn) throws {
        DispatchQueue.checkTurnQueue(self)
        guard let historyAccess = historyAccess else {
            log(.error, "Call to restore history but history access not configured")
            fatalError()
        }

        // 1 - get data from store
        var turnData = try historyAccess.loadDataForTurn(turn)
        var turnDataChanged = false

        // 2 - fan restored data out to clients
        try clients.forEach { name, historical in
            guard var historicalTurnData = turnData[name] else {
                log(.info, "Historical \(name) nothing found in turn data; continuing with restore")
                return
            }

            guard historicalTurnData.version <= historical.historyVersion else {
                let versionMsg = "Turn data for \(name) is version \(historicalTurnData.version) but " +
                                 "historical declared support only for \(historical.historyVersion)"
                log(.warning, versionMsg)
                throw RestoreError(details: versionMsg)
            }

            if historicalTurnData.version < historical.historyVersion {
                let newVersionData = try historical.convert(from: historicalTurnData.turnData,
                                                            atVersion: historicalTurnData.version,
                                                            usingDecoder: jsonDecoder,
                                                            usingEncoder: jsonEncoder)
                historicalTurnData = HistoricalTurnData(turnData: newVersionData, version: historical.historyVersion)
                turnData[name] = historicalTurnData
                turnDataChanged = true
            }

            try historical.restoreHistory(from: historicalTurnData.turnData, using: jsonDecoder)
        }

        // 3 - if any clients did an upgrade, re-save the data
        if turnDataChanged {
            try historyAccess.setDataForTurn(turn, data: turnData)
        }

        // 4 - fan restore-complete out to clients
        clients.forEach { name, historical in
            historical.restoreComplete()
        }
    }
}
