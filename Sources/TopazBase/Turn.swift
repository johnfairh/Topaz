//
//  Turn.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation

/// Convenience alias for the ID of a turn - treat it as a numeric.  The first turn of
/// the world is 1, each turn increments, the value does not wrap.
public typealias Turn = UInt64

extension Turn {
    /// Value of `TurnSource.thisTurn` during world initialization, before the first turn.
    /// Again: a turn with this number is never executed.
    static var INITIAL_TURN: Turn { return 0 }
}
