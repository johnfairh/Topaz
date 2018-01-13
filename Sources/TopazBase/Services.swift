//
//  Services.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Dispatch

/// Bundle of a complete set of Topaz services
public struct Services {
    /// The queue on which turns execute.  Must use this queue to talk to `TurnSource` for example.
    public let turnQueue: DispatchQueue

    /// Generate turns
    public let turnSource: TurnSource

    /// Create a new set of Topaz services
    public init(logMessageHandler: @escaping LogMessage.Handler) {
        turnQueue = DispatchQueue(label: DispatchQueue.TOPAZ_LABEL)
        turnSource = TurnSource(queue: turnQueue, logMessageHandler: logMessageHandler)
    }
}

/// Shenanigans to deal with policing the turn queue rules.
extension DispatchQueue {
    /// Identify our queue
    fileprivate static var TOPAZ_LABEL: String { return "TopazTurnQueue" }

    /// h/t Brent R-G...
    private static var currentQueueLabel: String? {
        let name = __dispatch_queue_get_label(nil)
        return String(cString: name, encoding: .utf8)
    }

    /// Validate the current thread is executing on the turn queue.  Panics if not.
    public static func checkTurnQueue(_ logger: LogMessageEmitter?) {
        let currentLabel = currentQueueLabel
        if let label = currentLabel,
            label == TOPAZ_LABEL {
            return // all good!
        }
        if let logger = logger {
            logger.log(.error, "Thread not on turn queue, found \(currentLabel ?? "(no label)")")
            fatalError()
        }
    }
}