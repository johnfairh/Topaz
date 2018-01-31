//
//  TestTurnSource.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import TopazBase

/// Test turn source (and by side-effect, lower-level Services setup)
class TestTurnSource: TestCase {

    /// Sanity check everything comes up
    func testWorldSetup() {
        let world = createDefaultWorld()
        world.services.printDebugString()
        world.services.historian.historyAccess = nil
        world.services.printDebugString()
    }

    /// Test manual turn progression
    func testManualTurn() {
        let world = createDefaultWorld()
        let expectedTurn = Turn(1)
        var turnReceived = false

        world.services.turnSource.register { turn in
            XCTAssertFalse(turnReceived)
            XCTAssertEqual(expectedTurn, turn)
            turnReceived = true
        }

        world.turn(1)

        XCTAssertTrue(turnReceived)
    }

    /// Test auto turn progression
    func testAutoTurn() {
        let world = createDefaultWorld()
        let turnStop = Turn(4)

        world.services.turnSource.register { turn in
            XCTAssertTrue(turn <= turnStop)
            if turn == turnStop {
                world.stopMainLoopAsync()
            }
        }

        let oldTurnPeriodMs = UInt32(400)

        world.services.turnQueue.sync {
            world.services.turnSource.progress = .automatic(milliseconds: oldTurnPeriodMs)
        }

        world.runMainLoop()

        XCTAssertEqual(turnStop, world.services.turnSource.thisTurn)

        let newTurnPeriodMs = UInt32(600)

        // This is a test for deser of .automatic progress
        world.services.turnQueue.sync {
            world.services.turnSource.progress = .automatic(milliseconds: newTurnPeriodMs)
        }

        world.setCurrentTurn(2)
        switch world.services.turnSource.progress {
        case .automatic(let period):
            XCTAssertEqual(oldTurnPeriodMs, period)
        default:
            XCTFail("TurnSource progress unexpected - \(world.services.turnSource.progress)")
        }
    }

    /// Test client policing post-startup
    func testLaterClientReg() {
        let world = createDefaultWorld()

        world.turn(1)

        var turnReceived = false
        world.services.turnQueue.sync {
            world.services.turnSource.register { turn in
                XCTAssertFalse(turnReceived)
                turnReceived = true
            }
        }

        world.turn(2)
        XCTAssertTrue(turnReceived)
    }
}
