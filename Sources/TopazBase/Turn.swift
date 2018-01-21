//
//  Turn.swift
//  TopazBase
//
//  Created by John Fairhurst on 21/01/2018.
//

import Foundation

/// Convenience alias for the ID of a turn - treat it as a numeric.  The first turn of
/// the world is 1, each turn increments, the value does not wrap.
public typealias Turn = UInt64

extension Turn {
    /// Value of `TurnSource.thisTurn` during world initialization, before the first turn
    static var INITIAL_TURN: Turn { return 0 }
}
