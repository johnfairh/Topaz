//
//  TestTurnSource.swift
//  TopazTests
//
//  Created by John Fairhurst on 29/01/2018.
//

import XCTest
import TopazBase

/// Test turn source (and by side-effect, lower-level Services setup)
class TestTurnSource: TestCase {

    func createDefaultWorld() -> TestWorld{
        let world = TestWorld()
        doNoThrow {
            try world.setDefaultHistory()
        }
        return world
    }

    /// Sanity check everything comes up
    func testWorldSetup() {
        let _ = createDefaultWorld()
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

        world.services.turnQueue.sync {
            world.services.turnSource.turn()
        }

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

        world.services.turnQueue.sync {
            world.services.turnSource.progress = .automatic(milliseconds: 400)
        }

        world.runMainLoop()

        XCTAssertEqual(turnStop, world.services.turnSource.thisTurn)
    }
}
