//
//  TestHistorian.swift
//  TopazTests
//
//  Created by John Fairhurst on 29/01/2018.
//

import XCTest
import TopazBase

/// Programably badly-behaved history client.
class TestHistorical: Historical {
    var historyName = "TestHistorical"
    
    struct State: Codable {
        var value: Int
    }

    var state = State(value: 0)

    func saveHistory(using encoder: JSONEncoder) -> Data {
        return try! encoder.encode(state)
    }

    /// push to make the next one restore fail
    var failNextRestore = false

    func restoreHistory(from data: Data, using decoder: JSONDecoder) throws {
        guard !failNextRestore else {
            failNextRestore = false
            throw TopazError("TestHistorical programmed to fail next restore")
        }
        state = try! decoder.decode(State.self, from: data)
    }
}

/// Test saving + restoring of history
class TestHistorian: TestCase {

    var historical: TestHistorical!

    override func createDefaultWorld() -> TestWorld {
        let world = super.createDefaultWorld()
        historical = TestHistorical()
        world.services.historian.register(historical: historical)
        return world
    }

    /// Basic save and restore
    func testRewindFfwd() {
        let world = createDefaultWorld()
        let turn1Value = 55
        let firstTurn2Value = 1004
        let secondTurn2Value = 41511
        let turn3Value = 1230

        historical.state.value = turn1Value
        world.turn(1)
        historical.state.value = firstTurn2Value
        world.turn(2)

        // Rewind + check
        world.setCurrentTurn(1)
        XCTAssertEqual(2, world.services.turnSource.nextTurn)
        XCTAssertEqual(turn1Value, historical.state.value)

        // New version of turn 2!
        historical.state.value = secondTurn2Value
        world.turn(2)
        historical.state.value = turn3Value
        world.turn(3)

        world.setCurrentTurn(2)
        XCTAssertEqual(secondTurn2Value, historical.state.value)

        // Now forward in time
        world.setCurrentTurn(3)
        XCTAssertEqual(turn3Value, historical.state.value)

        // Check can't go into future that hasn't happened
        doThrow {
            try world.services.turnQueue.sync {
                try world.services.setCurrentHistoryTurn(400)
            }
            XCTFail("Unexpected changed current turn to 400")
        }
    }
}
