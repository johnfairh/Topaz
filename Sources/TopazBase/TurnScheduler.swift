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
/// [serialization: generates token, stored by client, client uses to reclaim after deser?
///  or allows client to query remaining time, client must store + reestablish on deser]
///
/// Allows clients to cancel previously-scheduled callbacks.
///
struct TurnScheduler {//: LogMessageEmitter {
//    var logMessageHandler: LogMessage.Handler = nil
}
