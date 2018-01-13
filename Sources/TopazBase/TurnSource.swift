//
//  TurnSource.swift
//  Topaz
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation
import Dispatch

/// Convenience alias for the ID of a turn - treat it as a numeric.  The first turn of
/// the world is 1, each turn increments, the value does not wrap.
public typealias Turn = UInt64

extension Turn {
    /// Value of `TurnSource.thisTurn` during world initialization, before the first turn
    static var INITIAL_TURN: Turn { return 0 }
}

public final class TurnSource: LogMessageEmitter {
    /// Queue that everything runs on
    private var queue: DispatchQueue

    /// Logger
    public var logMessageHandler: LogMessage.Handler
    public let logMessagePrefix = "TurnSource"

    /// The turn that is happing right now
    public private(set) var thisTurn: Turn

    /// The next turn
    public var nextTurn: Turn {
        return thisTurn + 1
    }

    /// Clients registered for new turns
    public typealias Client = (Turn, TurnSource) -> Void

    private var clients: Array<Client>

    /// Add a client.  No way to remove clients, expected to be static linkage.
    public func register(client: @escaping Client) {
        if thisTurn > Turn.INITIAL_TURN {
            DispatchQueue.checkTurnQueue(self)
        }
        clients.append(client)
    }

    /// Start the next turn
    private func newTurn() {
        guard nextTurn != 0 else {
            log(.error, "Turn limit reached, the end.")
            fatalError()
        }
        thisTurn = nextTurn
        log(.info, "Starting turn \(self.thisTurn)")
        clients.forEach { $0(thisTurn, self) }
    }

    /// Rules for turn progression
    public enum Progress: CustomStringConvertible {
        /// Turns occur only when manually called for
        case manual

        /// Turns occur automatically with the given gap between them.
        /// Note that this is not the time between successive turn starts, it is the time
        /// between the end of one turn and the start of the next.
        case automatic(milliseconds: UInt32)

        public var description: String {
            switch self {
            case .manual: return "manual"
            case .automatic(let ms): return "auto(\(ms)ms)"
            }
        }
    }

    /// Timer for automatic progress.  `nil` in manual mode.
    private var timer: DispatchSourceTimer?

    private func cancelTimer() {
        timer = nil
    }

    private func startTimer(_ milliseconds: UInt32) {
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        timer = newTimer
        newTimer.setEventHandler(handler: { self.tickTimer() })
        newTimer.schedule(deadline: DispatchTime.now() + .milliseconds(1000))
        newTimer.resume()
    }

    private func tickTimer() {
        guard case let .automatic(milliseconds) = progress else {
            log(.warning, "Timer ticked but progress set to manual")
            fatalError() // For now
        }
        newTurn()
        startTimer(milliseconds)
    }

    /// Change the progress mode of the `TurnSource`
    /// If used to change the period of automatic progress then the current elapsed period is
    /// ignored -- an entire new period will elapse before the next turn.
    public var progress: Progress {
        willSet {
            DispatchQueue.checkTurnQueue(self)
            log(.info, "Changing progress from \(self.progress) to \(newValue)")
            if case .automatic(_) = progress {
                cancelTimer()
            }
        }
        didSet {
            if case .automatic(let milliseconds) = progress {
                startTimer(milliseconds)
            }
        }
    }

    /// Request a turn
    public func turn() {
        DispatchQueue.checkTurnQueue(self)
        guard case .manual = progress else {
            log(.warning, "Manual turn requested but progress is \(self.progress)")
            fatalError() // For now
        }
        newTurn()
    }

    /// Create a new `TurnSource` in `Progress.manual` mode
    public init(queue: DispatchQueue, logMessageHandler: @escaping LogMessage.Handler) {
        self.queue = queue
        self.logMessageHandler = logMessageHandler
        self.thisTurn = Turn.INITIAL_TURN
        self.clients = []
        self.progress = .manual
    }
}

extension TurnSource: CustomStringConvertible {
    public var description: String {
        return "\(logMessagePrefix) thisTurn=\(thisTurn) progress=\(progress)"
    }
}
