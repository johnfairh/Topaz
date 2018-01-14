//
//  History.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//
import Foundation

/// History stores a version number along with each client's data.
/// Clients can use this to orchestrate changes in their history data.
public typealias HistoryVersion = UInt32

extension HistoryVersion {
    /// All client data starts with a version of zero
    static var FIRST_VERSION: HistoryVersion { return 0 }
}

/// Clients access history using regular `Codable` classes.  They implement `Encodable`
/// to save data but restore is done via a `Historical.restore(from:)` method instead of the `Decodable`
/// constructor.
///
/// World restore has two phases.  First each client restores their own data from the history.
/// Then when all are done the `Historical.restoreComplete` method is called to let clients
/// reestablish relationships.  If we run into dependency problems here then will have to fix.
///
/// History offers a versioning story; clients are free to use this or do their own thing against
/// their own datastore.  The `Historical.historyVersion` and `Historical.convert(...)`
/// fields are optional.
public protocol Historical: Encodable {
    /// Restore the client's state from the decoder.  The data is guaranteed to be at version `historyVersion`.
    func restore(from decoder: Decoder) throws
    /// Called when all clients have been decoded OK.
    func restoreComplete()

    /// What version of history does the client expect in `restore(...)`?
    var historyVersion: HistoryVersion { get }
    /// Convert a historical record from `atVersion` to the current `historyVersion` -- which
    /// will be persisted replacing the old one, then (probably) passed to `restore(...)`.
    func convert(from decoder: Decoder, atVersion: HistoryVersion, to encoder: Encoder) throws
}

/// Default implementations for `Historical`
extension Historical {
    /// By default do nothing
    func restoreComplete() {}

    /// By default return `HistoryVersion.FIRST_VERSION`
    var historyVersion: HistoryVersion { return .FIRST_VERSION }

    /// By default fail if asked to convert versions
    func convert(from decoder: Decoder, atVersion: HistoryVersion, to encoder: Encoder) throws {
        throw RestoreError(details: "HistoryStorable.convert unimplemented, can't convert from \(atVersion) to \(historyVersion)")
    }
}

/// XXX move to ErrorHandling.swift or something
public struct RestoreError: Error {
    public let underlyingError: Error?
    public var details: String

    public init(underlyingError: Error) {
        self.underlyingError = underlyingError
        self.details = ""
    }
    public init(details: String) {
        self.underlyingError = nil
        self.details = details
    }
}

/// The data stored per client per turn
public struct HistoricalTurnData: Codable {
    /// Encoded client data
    public let turnData: Data
    /// `HistoryVersion` of `turnData`
    public let version: HistoryVersion
}

/// A place that world state is saved to and loaded from.
///
/// (This protocol is a bit smelly: its load/save methods are only for `Historian` while
/// the metadata ones are for the UI layer -- feel like no real gain to splitting them
/// up right now though.)
public protocol History {
    /// User-friendly name associated with the `History`
    var name: String { get }
    /// Time that the `History` was last updated
    var accessTime: Date { get }
    /// Set of `Turn`s that the `History` covers
    var turns: Range<Turn> { get }

    /// Create or update the data for the given `Turn`
    func save(turn: Turn, data: [String : HistoricalTurnData]) throws
    /// Retrieve the data for the given `Turn`
    func load(turn: Turn) throws -> [String : HistoricalTurnData]
}

/// A manager of alternative `History`s
public protocol HistoryStore {
    /// Available `History`s.  Can be empty.
    var histories: [History] { get }

    /// Delete an existing `History`.  Not the one the world is in please.
    func delete(history: History) throws

    /// Create a fresh `History`.  Name must be unique.
    func createEmpty(name: String) throws -> History
}

/// Helpers
public extension HistoryStore {
    /// Return a sensible `History` from the store: either the most recently accessed or
    /// a fresh one if the store is empty.
    public func getLatestHistory(newlyNamed: String) throws -> History {
        if let mostRecentHistory = (histories.sorted { h1, h2 in h1.accessTime < h2.accessTime }).first {
            return mostRecentHistory
        } else {
            return try createEmpty(name: newlyNamed)
        }
    }
}

/// This class records changes to world state as turns progress.  It also deals with
/// restoring the world to match a previously recorded state.
///
/// It has a `History` that actually persists world state; components that
/// want to be part of history register a `Historical` instance along with a
/// `String` ID.
///
/// Restoration works by pausing turns, overwriting existing state, allowing
/// components to reestablish relationships, and then resuming turns.
final public class Historian: LogMessageEmitter {
    /// Logger
    public var logMessageHandler: LogMessage.Handler
    public let logMessagePrefix = "Historian"

    private var history: History?

    private var clients: [String : Historical]

    public func register(client: Historical, withId id: String) {
        guard clients[id] == nil else {
            fatalError()
        }
        clients[id] = client
    }

    public init(logMessageHandler: @escaping LogMessage.Handler) {
        self.logMessageHandler = logMessageHandler
        self.history = nil
        self.clients = [:]
    }
}
