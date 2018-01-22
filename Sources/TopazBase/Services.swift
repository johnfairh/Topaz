//
//  Services.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Dispatch

/// Bundle of a complete set of Topaz services
public struct Services {
    /// Central store of debug state reporting
    public let debugDumper: DebugDumper

    /// The queue on which turns execute.  Must use this queue to talk to `TurnSource` for example.
    public let turnQueue: DispatchQueue

    /// Create and modify history
    public let historian: Historian

    /// Generate turns
    public let turnSource: TurnSource

    /// Create a new set of Topaz services
    public init(logMessageHandler: @escaping LogMessage.Handler) {
        debugDumper = DebugDumper(logMessageHandler: logMessageHandler)
        turnQueue = DispatchQueue.createTurnQueue()
        historian = Historian(debugDumper: debugDumper)
        turnSource = TurnSource(queue: turnQueue, historian: historian, debugDumper: debugDumper)
    }
}

// MARK: - DebugDumper helpers

extension Services {
    /// Collect a debug dump of the system
    public var debugString: String {
        return debugDumper.description
    }

    /// Print a debug dump of the system
    public func printDebugString() {
        print(debugString)
    }
}

// MARK: - History restore helpers

extension Services {
    /// Coordinate between services to set up the world in a new state.
    /// Must be called on the turn queue.
    public func setNewHistory(_ historyAccess: HistoryAccess) throws {
        DispatchQueue.checkTurnQueue()
        historian.historyAccess = historyAccess

        if let latestTurn = historyAccess.mostRecentTurn {
            try historian.restoreAtTurn(latestTurn)
        } else {
            guard turnSource.thisTurn == .INITIAL_TURN else {
                // TODO: do better?
                fatalError("Attempting to set a new history that is empty, so cannot be restored from, " +
                           "onto a world that is not at INITIAL_TURN.")
            }
        }
        turnSource.restartAfterRestore()
    }

    /// Coordinate between services to move the world to a different turn in
    /// the current history.  Must be called on the turn queue.
    public func setCurrentHistoryTurn(_ turn: Turn) throws {
        DispatchQueue.checkTurnQueue()
        try historian.restoreAtTurn(turn)
        turnSource.restartAfterRestore()
    }
}

