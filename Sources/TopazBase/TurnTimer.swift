//
//  TurnScheduler.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation

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

///
/// Center point for orchestrating activity on later `Turn`s.
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

    /// Debug generation of token IDs
    private var nextTokenId = UInt64.min
    private func getTokenId() -> UInt64 {
        defer { nextTokenId += 1 }
        return nextTokenId
    }

    /// Track a client timer
    final class Token: TurnTimerToken, CustomStringConvertible {
        /// Client's callback
        let client: TurnTimerClient

        /// Debug token
        let tokenId: UInt64

        /// Is this timer repeating?  If so, how long?
        let repeatPeriod: TurnCount?
        /// For debug, the original period of the timer.
        let originalPeriod: TurnCount
        /// See algorithm above
        var relativeDelay: TurnCount

        /// Back-ref to module to implement convenience methods.  Set nil when the
        /// token is taken off the queue or cancelled (has ticked its last).
        weak var turnTimer: TurnTimer?

        /// Create a new token
        init(originalPeriod: TurnCount, repeatPeriod: TurnCount?, client: TurnTimerClient, tokenId: UInt64) {
            self.relativeDelay = 0
            self.originalPeriod = originalPeriod
            self.repeatPeriod = repeatPeriod
            self.client = client
            self.tokenId = tokenId
        }

        /// How long until this timer fires -- have to go out to add up the queue
        var turnsUntilNextTick: TurnCount {
            return turnTimer?.turnsUntilNextTick(of: self) ?? 0
        }

        /// Halt the timer.  Leave it on the queue for speed.
        func cancel() {
            turnTimer?.log(.info, "Cancelling timer TokenId=\(self.tokenId)")
            turnTimer = nil
        }

        /// Has the timer been cancelled?
        var isCancelled: Bool {
            return turnTimer == nil
        }

        /// Helper - tick the timer and mark it as cancelled
        func tick() {
            client.tick()
            turnTimer = nil
        }

        /// Debug description - don't want to compute expensive 'to go' property
        var description: String {
            let repeatStr = (repeatPeriod != nil) ? " repeating=\(repeatPeriod!)" : ""
            let cancelStr = (turnTimer == nil) ? " cancelled" : ""
            return "Id=\(tokenId) period=\(originalPeriod) relative=\(relativeDelay)\(repeatStr)\(cancelStr)"
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

        let token = Token(originalPeriod: after, repeatPeriod: repeatingEvery, client: client, tokenId: getTokenId())

        scheduleToken(token, after: after)

        return token
    }

    /// Schedule the token - common part of schedule() + reschedule()
    private func scheduleToken(_ token: Token, after: TurnCount) {
        // Note!  It is very possible for this to be called as part of a tick() callback.
        // This means we may be in the midst of dispatching a group of tokens that are due
        // this tick.
        // And so it would be **wrong** to assume/assert that HOQ has relativeDelay of 0.
        // This is the only case where we can end up with `token.relativeDelay` equal to
        // `token.originalPeriod` -- it has been put into the queue after a prefix of tokens
        // with relative=0.

        token.turnTimer = self

        // assume the worst case + adjust as we go
        token.relativeDelay = after

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
    }

    /// Called every turn to process timers.
    public func turnStart(turn: Turn) {
        // fastpath out
        guard let headOfQueue = tokenQueue.first else {
            return
        }

        // count down the head of queue, it is the only one counting.
        guard headOfQueue.relativeDelay > 0 else {
            fatal("Timer token queue broken, head has 0 delta at start of turn")
        }
        headOfQueue.relativeDelay -= 1

        // fastpath out again
        guard headOfQueue.relativeDelay == 0 else {
            return
        }

        // now dispatch the prefix of the queue with 0 relative time -- these are all due now.
        while let token = tokenQueue.first,
            token.relativeDelay == 0 {

            tokenQueue.removeFirst() // yuck data structure
            if !token.isCancelled {
                token.tick()
                if let repeatPeriod = token.repeatPeriod {
                    // schedule it again
                    scheduleToken(token, after: repeatPeriod)
                }
            }
        }
    }

    /// Scan the queue to find the cumulative time until the token ticks.
    private func turnsUntilNextTick(of token: Token) -> TurnCount {
        var turns = TurnCount(0)
        for nextToken in tokenQueue {
            turns += nextToken.relativeDelay
            if token === nextToken {
                break
            }
        }
        return turns
    }
}

// MARK: - CustomStringConvertible

extension TurnTimer: CustomStringConvertible {
    public var description: String {
        let sb = StringBuilder()
        sb.line("\(tokenQueue.count) timers scheduled, next token ID \(nextTokenId)")
        sb.in()
        tokenQueue.forEach { token in
            sb.line(token.description)
        }
        sb.out()
        return sb.string
    }
}
