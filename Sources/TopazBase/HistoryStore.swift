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
    var name: String { get }

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
    public func getLatestHistory(newlyNamed: String) throws -> History {
        if let mostRecentHistory = (histories.sorted { h1, h2 in h1.accessTime < h2.accessTime }).first {
            return mostRecentHistory
        } else {
            return try createEmpty(name: newlyNamed)
        }
    }
}

// MARK: InMemoryHistoreStore

/// A sample history store for testing and debugging that keeps everything live in-memory.
public final class InMemoryHistoryStore: HistoryStore {
    /// In-memory history, stores all turns forever
    final class InMemoryHistory: History {
        let name: String
        var accessTime: Date
        var turnStore: [Turn : [String : HistoricalTurnData]]
        var highestTurn: Turn = .INITIAL_TURN
        var turns: Range<Turn> {
            return .INITIAL_TURN..<highestTurn
        }
        var active: Bool
        var clientData: Data?

        init(name: String) {
            self.name = name
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
                throw RestoreError(details: "History does not have turn \(turn), contents approx \(turns)")
            }
            return turnData
        }

        var mostRecentTurn: Turn? {
            return highestTurn == .INITIAL_TURN ? nil : highestTurn
        }

        var description: String {
            return "InMemoryHistory \(name) turns \(turns) last accessed \(accessTime)"
        }
    }

    private var historyStore: [String : InMemoryHistory] = [:]

    public var histories: [History] {
        return Array(historyStore.values)
    }

    public func delete(history: History) throws {
        guard let _ = historyStore[history.name] else {
            throw RestoreError(details: "Don't have history called \(history.name)")
        }
        guard !history.active else {
            throw RestoreError(details: "Can't delete active history \(history.name)")
        }
        historyStore[history.name] = nil
    }

    public func createEmpty(name: String) throws -> History {
        guard historyStore[name] == nil else {
            throw RestoreError(details: "Already have history called \(name), can't create a new one")
        }
        let history = InMemoryHistory(name: name)
        historyStore[name] = history
        return history
    }

    public init() {}
}
