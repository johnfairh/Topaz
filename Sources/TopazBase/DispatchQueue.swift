//
//  DispatchQueue.swift
//  TopazBase
//
//  Created by John Fairhurst on 22/01/2018.
//

import Dispatch

/// Shenanigans to deal with policing the turn queue rules.
extension DispatchQueue {
    /// Identify our queue
    private static var TOPAZ_LABEL: String { return "TopazTurnQueue" }

    /// Create the turn queue
    internal static func createTurnQueue() -> DispatchQueue {
        return DispatchQueue(label: DispatchQueue.TOPAZ_LABEL)
    }

    /// h/t Brent R-G...
    private static var currentQueueLabel: String? {
        let name = __dispatch_queue_get_label(nil)
        return String(cString: name, encoding: .utf8)
    }

    /// Validate the current thread is executing on the turn queue.  Panics if not.
    public static func checkTurnQueue(_ logger: Logger? = nil) {
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
