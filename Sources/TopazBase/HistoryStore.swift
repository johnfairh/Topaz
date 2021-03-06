//
//  HistoryStore.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation

/// A world history along with associated metadata.
public protocol History: HistoryAccess {
    /// User-friendly name associated with the `History`
    var historyName: String { get }

    /// Time that the `History` was last updated
    var accessTime: Date { get }

    /// Set of `Turn`s that the `History` covers
    var turns: Range<Turn> { get }

    /// Opaque client data.  Must be cheap to access.
    var clientData: Data? { set get }
}

/// A manager of alternative `History`s
public protocol HistoryStore {
    /// Available `History`s.  Can be empty.  Must be cheap to access
    var histories: [History] { get }

    /// Delete an existing `History`.  Not the one the world is in please.
    func delete(history: History) throws

    /// Create a fresh `History`.  Name must be unique within this `HistoryStore`.
    func createEmpty(name: String) throws -> History
}

public extension HistoryStore {
    /// Return a sensible `History` from the store: either the most recently accessed or
    /// a fresh one if the store is empty.
    func getLatestHistory(newlyNamed: String) throws -> History {
        if let mostRecentHistory = (histories.sorted { h1, h2 in h1.accessTime > h2.accessTime }).first {
            return mostRecentHistory
        }
        return try createEmpty(name: newlyNamed)
    }
}

// MARK: InMemoryHistoreStore

/// A sample history store for testing and debugging that keeps everything live in-memory.
public final class InMemoryHistoryStore: HistoryStore, DebugDumpable {
    /// In-memory history, stores all turns forever
    final class InMemoryHistory: History {
        let historyName: String
        var accessTime: Date
        var turnStore: [Turn : [String : HistoricalTurnData]]
        var highestTurn: Turn = .INITIAL_TURN
        var empty: Bool {
            return highestTurn == .INITIAL_TURN
        }
        var turns: Range<Turn> {
            return empty ? .INITIAL_TURN ..< .INITIAL_TURN : .INITIAL_TURN+1..<highestTurn+1
        }
        var active: Bool
        var clientData: Data?

        init(name: String) {
            self.historyName = name
            self.accessTime = Date()
            self.turnStore = [:]
            self.active = false
            self.clientData = nil
        }

        func setDataForTurn(_ turn: Turn, data: [String : HistoricalTurnData]) throws {
            turnStore[turn] = data
            highestTurn = max(highestTurn, turn)
            accessTime = Date()
        }

        func loadDataForTurn(_ turn: Turn) throws -> [String : HistoricalTurnData] {
            guard let turnData = turnStore[turn] else {
                throw TopazError("History does not have turn \(turn), contents approx \(turns)")
            }
            return turnData
        }

        var mostRecentTurn: Turn? {
            return empty ? nil : highestTurn
        }

        var description: String {
            return "\(historyName) turns \(turns) last accessed \(accessTime)"
        }
    }

    private var historyStore: [String : InMemoryHistory] = [:]

    public var histories: [History] {
        return Array(historyStore.values)
    }

    public func delete(history: History) throws {
        guard let _ = historyStore[history.historyName] else {
            throw TopazError("Don't have history called \(history.historyName)")
        }
        guard !history.active else {
            throw TopazError("Can't delete active history \(history.historyName)")
        }
        historyStore[history.historyName] = nil
    }

    public func createEmpty(name: String) throws -> History {
        guard historyStore[name] == nil else {
            throw TopazError("Already have history called \(name), can't create a new one")
        }
        let history = InMemoryHistory(name: name)
        historyStore[name] = history
        return history
    }

    /// Create a fresh, empty, in-memory store
    public init(debugDumper: DebugDumper) {
        debugDumper.register(debugDumpable: self)
    }

    // MARK: - Debug

    /// Debug key
    public var debugName = "InMemoryHistoryStore"

    /// Describe everything
    public var description: String {
        let sb = StringBuilder()
        sb.line("\(historyStore.count) histories")
        sb.in()
        historyStore.forEach { key, history in
            sb.line("History \(key)")
            sb.in()
              .line(history.description)
              .out()
        }
        return sb.string
    }
}
