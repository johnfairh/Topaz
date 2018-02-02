//
//  TestTurnTimer.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import TopazBase

class TestTurnTimer: TestCase {

    /// Test basic function
    func testSingleShot() {
        let world = createDefaultWorld()

        world.turn(1)

        var timerTicked = false
        let timerPeriod = TurnCount(2)
        let timerExpected = world.services.turnSource.thisTurn + timerPeriod

        let _ = world.scheduleTimer(after: timerPeriod) {
            DispatchQueue.checkTurnQueue()
            XCTAssertFalse(timerTicked)
            XCTAssertEqual(world.services.turnSource.thisTurn, timerExpected)
            timerTicked = true
        }
        print("TurnTimer: \(world.services.turnTimer)")

        world.turn(2)
        XCTAssertFalse(timerTicked)
        world.turn(3)
        XCTAssertTrue(timerTicked)
        world.turn(4)
        world.turn(5)
    }

    /// Test basic repeating timer
    func testRepeating() {
        let world = createDefaultWorld()

        world.turn(1)

        var timerTickCount = 0
        let timerPeriod = TurnCount(2)
        let timerExpected = [world.services.turnSource.thisTurn + timerPeriod,
                             world.services.turnSource.thisTurn + timerPeriod * 2,
                             world.services.turnSource.thisTurn + timerPeriod * 3]

        let timer = world.scheduleTimer(after: timerPeriod, repeatingEvery: timerPeriod) {
            timerTickCount += 1
            XCTAssertTrue(timerExpected.contains(world.services.turnSource.thisTurn))
        }
        print("TurnTimer: \(world.services.turnTimer)")

        (2..<9).forEach { world.turn($0) }
        XCTAssertEqual(3, timerTickCount)
        timer.cancel()
        print("TurnTimer: \(world.services.turnTimer)")
        world.turn(9)
        XCTAssertEqual(3, timerTickCount)
    }

    /// Test multiple timers - exercise actual queue code
    func testMultipleTimers() {
        let world = createDefaultWorld()

        // repeating timers for two, three, and four turns - covers all bases
        var twoTickTimerTicks = 0
        var threeTickTimerTicks = 0
        var fourTickTimerTicks = 0
        let timer2 = world.scheduleTimer(after: 2, repeatingEvery: 2) { twoTickTimerTicks += 1 }
        let timer3 = world.scheduleTimer(after: 3, repeatingEvery: 3) { threeTickTimerTicks += 1 }
        let timer4 = world.scheduleTimer(after: 4, repeatingEvery: 4) { fourTickTimerTicks += 1 }

        print("TurnTimer: \(world.services.turnTimer)")

        (1..<13).forEach { world.turn($0) }

        XCTAssertEqual(6, twoTickTimerTicks)
        XCTAssertEqual(4, threeTickTimerTicks)
        XCTAssertEqual(3, fourTickTimerTicks)

        XCTAssertEqual(2, timer2.turnsUntilNextTick)
        XCTAssertEqual(3, timer3.turnsUntilNextTick)
        XCTAssertEqual(4, timer4.turnsUntilNextTick)

        // move on a bit to get some zeroes in there
        world.turn(13)
        world.turn(14)

        XCTAssertEqual(2, timer2.turnsUntilNextTick)
        XCTAssertEqual(1, timer3.turnsUntilNextTick)
        XCTAssertEqual(2, timer4.turnsUntilNextTick)
    }
}
