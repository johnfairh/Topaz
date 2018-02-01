//
//  TurnScheduler.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation

///
/// Center point for orchestrating activity `Turn`s.
///
/// Registers with `TurnSource` to know about each turn starting.
///
/// Allows clients to schedule callbacks:
/// * "Call me at Turn X"
/// * "Call me after Y Turns"
/// * "Call me every Z Turns"
/// * "Call me after Y, and then after every Z Turns"
///
/// Allows clients to cancel previously-scheduled callbacks.
/// We are single-threaded on the turn queue so for once this is ezpz.
///
/// Serialization.
/// Issue is we cannot serialize the callback itself, so must do some kind of dance
/// to reassert the link.
///
/// 1) Timer generates token.  Client queries token at client ser time to get remaining
///    ticks and saves that number.  Client desers the number and creates new timer.
///    TurnSched itself does not serialize anything.
///
/// 2) Timer generates token.  Client serializes token, provides to TurnSched on deser
///    along with callback to reestablish link.  TurnSched ser + deser the queue and
///    its tokens.
///
/// I think go with (1), more flexibility for clients to change behaviour at upgrade time.
/// Means clients will have aux ser state struct to contain this stuff.  Fair enough.  Better
/// than odd proxy model in TurnSource tbf.  Rst is rare so don't care about overheads of
/// rebuilding the queue.
///

/// Object returned to client to track a timer.  Properties do nothing useful after
/// the timer has finished.
public protocol TurnTimerToken {
    /// (fairly expensive) how many turns until the next tick?  Typically used for debug or serialization.
    var turnsUntilNextTick: TurnCount { get }
    /// Cancel the timer.
    func cancel()
}

/// Protocol adopted to receive a scheduled callback
public protocol TurnTimerClient {
    /// Callback made when timer conditions are met.
    /// If the timer was oneshot then it is not scheduled any more.
    /// If the timer was multishot then it has been rescheduled for the next tick.
    func tick()
}


public final class TurnTimer : DebugDumpable, Logger, TurnSourceClient {
    /// Logger
    public let logMessageHandler: LogMessage.Handler

    /// DebugDumper
    public let debugName = "TurnTimer"

    /// ## Algorithm
    ///
    /// * Maintain a queue of `Token`s ordered by tick time.
    /// * Each `Token` stores a `relativeDelay` - the number of ticks after the previous guy in
    ///   the queue that it is due.
    /// * Each tick() event, look at HOQ and reduce `relativeDelay` by 1.  If this is now 0 then
    ///   dispatch that token along with all subsequent tokens that have a `relativeDelay` of 0.
    ///
    /// This means schedule() + cancel() are O(n) and tick is O(1) [Or, I guess, O(k) where k is
    /// the usual number of due tokens.  Hmm, although reschedule for repeating adds more O(n) ops
    /// so unclear where this goes then.

    /// List of tokens ordered in due time
    private var tokenQueue: Array<Token> // TODO use a more sensible data structure

    /// Track a client timer
    final class Token: TurnTimerToken {
        /// Client's callback
        let client: TurnTimerClient

        /// Is this timer repeating?  If so, how long?
        let repeatPeriod: TurnCount?
        /// For debug, the original period of the timer.
        let originalPeriod: TurnCount
        /// See algorithm above
        var relativeDelay: TurnCount

        /// Back-ref to module to implement convenience methods.  Set nil when the
        /// token is taken off the queue (has ticked its last)
        weak var turnTimer: TurnTimer?

        /// Create a new token
        init(relativeDelay: TurnCount, originalPeriod: TurnCount, repeatPeriod: TurnCount?, client: TurnTimerClient, turnTimer: TurnTimer) {
            self.relativeDelay = relativeDelay
            self.originalPeriod = originalPeriod
            self.repeatPeriod = repeatPeriod
            self.client = client
            self.turnTimer = turnTimer
        }

        /// How long until this timer fires -- have to go out to add up the queue
        var turnsUntilNextTick: TurnCount {
            return turnTimer?.turnsUntilNextTick(of: self) ?? 0
        }

        /// Get this timer off the queue
        func cancel() {
            turnTimer?.cancel(token: self)
        }
    }

    /// Create a new `TurnTimer` service instance
    init(turnSource: TurnSource, debugDumper: DebugDumper) {
        logMessageHandler = debugDumper.logMessageHandler
        tokenQueue = []
        turnSource.register(client: self)
    }

    /// Arrange for a callback to made after a number of turns have passed, and optionally repeat
    /// the callback every N turns thereafter.
    /// Must be called on the turn queue.
    public func schedule(after: TurnCount, repeatingEvery: TurnCount? = nil, callback: @escaping () -> Void) -> TurnTimerToken {
        struct Client: TurnTimerClient {
            let callback: () -> Void
            func tick() { callback() }
        }
        return schedule(client: Client(callback: callback), after: after, repeatingEvery: repeatingEvery)
    }

    /// Arrange for a callback to made after a number of turns have passed, and optionally repeat
    /// the callback every N turns thereafter.
    /// Must be called on the turn queue.
    public func schedule(client: TurnTimerClient, after: TurnCount, repeatingEvery: TurnCount? = nil) -> TurnTimerToken {
        DispatchQueue.checkTurnQueue(self)
        guard after > 0 else {
            fatal("Can't schedule timer after 0 turns")
        }
        guard repeatingEvery == nil || repeatingEvery! > 0 else {
            fatal("Can't schedule repeating timer with 0 repeat period")
        }

        let token = Token(relativeDelay: after, originalPeriod: after, repeatPeriod: repeatingEvery, client: client, turnTimer: self)

        // Note!  It is very possible for this to be called as part of a tick() callback.
        // This means we may be in the midst of dispatching a group of tokens that are due
        // this tick.
        // And so it would be **wrong** to assume/assert that HOQ has relativeDelay of 0.
        // This is the only case where we can end up with `token.relativeDelay` equal to
        // `token.originalPeriod` -- it has been put into the queue after a prefix of tokens
        // with relative=0.

        var inserted = false

        for index in 0..<tokenQueue.count {
            let nextToken = tokenQueue[index]
            if nextToken.relativeDelay <= token.relativeDelay {
                // we go somewhere after this one, account for its delay
                token.relativeDelay -= nextToken.relativeDelay
            } else {
                // we go before this one, adjust its delay
                nextToken.relativeDelay -= token.relativeDelay
                tokenQueue.insert(token, at: index)
                inserted = true
                break;
            }
        }
        // handle the case where we go after all of the current queue
        if !inserted {
            tokenQueue.append(token)
        }

        return token
    }

    public func turnStart(turn: Turn) {
        // TODO pump queue
    }

    private func turnsUntilNextTick(of token: Token) -> TurnCount {
        // TODO write me
        return 1
    }

    private func cancel(token: Token) {
        // TODO write me
    }
}

// MARK: - CustomStringConvertible

extension TurnTimer: CustomStringConvertible {
    public var description: String {
        return "TurnTimer"
    }
}
