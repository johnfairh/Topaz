//
//  TurnSource.swift
//  Topaz
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation
import Dispatch

/// Protocol to receive turn events
public protocol TurnSourceClient {
    func turnStart(turn: Turn)
}

/// Fundamental source of time events, generates turn notifications.
public final class TurnSource: DebugDumpable, Logger {
    /// Queue that everything runs on
    private let queue: DispatchQueue

    /// Historian assigned to checkpoint world state over turns
    private weak var historian: Historian?

    /// Logger
    public let logMessageHandler: LogMessage.Handler

    /// DebugDumper
    public let debugName = "TurnSource"

    /// Clients registered for new turns
    private var clients: Array<TurnSourceClient>

    /// Add a client.  No way to remove clients, expected to be static linkage -- transient/dynamic
    /// needs should be met using `TurnScheduler`.
    public func register(client: TurnSourceClient) {
        if thisTurn > Turn.INITIAL_TURN {
            DispatchQueue.checkTurnQueue(self)
        }
        clients.append(client)
    }

    /// Add a client as a closure for convenience
    public func register(callback: @escaping (Turn) -> Void) {
        struct Helper: TurnSourceClient {
            var callback: (Turn) -> Void
            func turnStart(turn: Turn) {
                callback(turn)
            }
        }
        register(client: Helper(callback: callback))
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

    /// State to be serialized
    fileprivate struct State: Codable {
        var thisTurn: Turn
        var progress: Progress

        init() {
            thisTurn = .INITIAL_TURN
            progress = .manual
        }
    }
    private var state: State

    /// The turn that is happing right now
    public private(set) var thisTurn: Turn {
        get { return state.thisTurn }
        set { state.thisTurn = newValue }
    }

    /// The next turn
    public var nextTurn: Turn {
        guard thisTurn < .max else {
            fatal("Turn limit reached, the end.")
        }
        return thisTurn + 1
    }

    /// Execute the next turn
    private func newTurn() {
        guard nextTurn != .INITIAL_TURN else {
            fatal("Confused about turn ordering, current turn is \(self.thisTurn)")
        }
        thisTurn = nextTurn
        log(.info, "Starting turn \(self.thisTurn)")
        clients.forEach { $0.turnStart(turn: thisTurn) }
        log(.info, "Adding turn \(self.thisTurn) to history")
        historian?.save(turn: thisTurn)
        log(.debug, "Turn \(self.thisTurn) added to history")
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
            // UI coding error - crash
            fatal("Timer ticked but progress set to manual")
        }
        newTurn()
        startTimer(milliseconds)
    }

    /// Change the progress mode of the `TurnSource`
    /// If used to change the period of automatic progress then the current elapsed period is
    /// ignored -- an entire new period will elapse before the next turn.
    public var progress: Progress {
        set {
            DispatchQueue.checkTurnQueue(self)
            log(.info, "Changing progress from \(self.progress) to \(newValue)")
            state.progress = newValue
            cancelTimer()
            if case .automatic(let milliseconds) = progress {
                startTimer(milliseconds)
            }
        }
        get {
            return state.progress
        }
    }

    /// Request a turn
    public func turn() {
        DispatchQueue.checkTurnQueue(self)
        guard case .manual = progress else {
            // Coding error - crash
            fatal("Manual turn requested but progress is \(self.progress)")
        }
        newTurn()
    }

    /// Create a new `TurnSource` in `Progress.manual` mode
    public init(queue: DispatchQueue, historian: Historian, debugDumper: DebugDumper) {
        self.queue = queue
        self.historian = historian
        self.logMessageHandler = debugDumper.logMessageHandler
        self.clients = []
        self.state = State()
        historian.register(historical: self)
        debugDumper.register(debugDumpable: self)
    }
}

// MARK: - Historical

extension TurnSource: Historical {
    /// Set up for a new world
    public func restoreInitialHistory() {
        self.state = State()
    }

    /// Save internal `State` struct.
    public func saveHistory(using encoder: JSONEncoder) -> Data {
        return try! encoder.encode(state)
    }

    /// Restore directly to the internal struct.  This bypasses the property
    /// setter for `progress` so the timer does not restart - wait until the
    /// restore is completely done and `restartAfterRestore` is called
    public func restoreHistory(from data: Data, using decoder: JSONDecoder) throws {
        state = try decoder.decode(State.self, from: data)
        log(.info, "Restored \(self)")
    }

    /// Restart the turnsource - called from the very outside at the end of a restore to get
    /// things going again.
    public func restartAfterRestore() {
        log(.info, "Restarting after restore complete")
        let progress = self.progress
        self.progress = progress
    }
}

// MARK: - CustomStringConvertible

extension TurnSource: CustomStringConvertible {
    /// Describe the component
    public var description: String {
        return "thisTurn=\(thisTurn) progress=\(progress)"
    }
}

// MARK: - History

/// Bit of a mess to serialize this thing because of the associated-type enum...
extension TurnSource.State {
    enum CodingKeys: CodingKey {
        case thisTurn
        case progressIsManual
        case progressAutoMilliseconds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thisTurn, forKey: .thisTurn)
        switch progress {
        case .manual:
            try container.encode(true, forKey: .progressIsManual)
        case .automatic(let milliseconds):
            try container.encode(milliseconds, forKey: .progressAutoMilliseconds)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        thisTurn = try values.decode(UInt64.self, forKey: .thisTurn)
        if values.contains(.progressIsManual) {
            progress = .manual
        } else {
            let period = try values.decode(UInt32.self, forKey: .progressAutoMilliseconds)
            progress = .automatic(milliseconds: period)
        }
    }
}
