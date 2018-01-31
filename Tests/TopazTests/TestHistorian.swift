//
//  TestHistorian.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import TopazBase

/// Programmably badly-behaved history client.
class TestHistorical: Historical {

    var historyName = "TestHistorical"

    var historyVersion = HistoryVersion(1)

    struct State: Codable {
        var value: Int
    }

    var state = State(value: 999)

    static let INITIAL_STATE_VALUE = 0

    func restoreInitialHistory() {
        state = State(value: TestHistorical.INITIAL_STATE_VALUE)
    }

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

    // record conversion occurred
    var converted = false

    func convert(from: Data, atVersion: HistoryVersion,
                 usingDecoder decoder: JSONDecoder, usingEncoder encoder: JSONEncoder) throws -> Data {
        XCTAssertEqual(HistoryVersion(1), atVersion)
        XCTAssertEqual(HistoryVersion(2), historyVersion)
        converted = true
        return from
    }

    // record restore-no-data-found occurred
    var noDataFound = false

    func restoreHistoryNoDataFound() throws {
        noDataFound = true
        state = State(value: 0)
    }
}

/// Programmably badly-behaved history storage
class TestHistoryAccess: HistoryAccess {
    var wrapped: HistoryAccess
    var failNextSave: Bool
    var failNextLoad: Bool
    var stripClientDataOnLoad: Bool
    var setClientDataVersionHighOnLoad: Bool
    var clientName: String

    var description: String {
        return "[TestHistoryAccess] \(wrapped.description)"
    }

    init(historyAccess: HistoryAccess) {
        self.wrapped = historyAccess
        self.failNextSave = false
        self.failNextLoad = false
        self.stripClientDataOnLoad = false
        self.setClientDataVersionHighOnLoad = false
        self.clientName = ""
    }

    func setDataForTurn(_ turn: Turn, data: [String : HistoricalTurnData]) throws {
        guard !failNextSave else {
            failNextSave = false
            throw TopazError("TestHistoryAccess.setDataForTurn")
        }
        try wrapped.setDataForTurn(turn, data: data)
    }

    func loadDataForTurn(_ turn: Turn) throws -> [String : HistoricalTurnData] {
        guard !failNextLoad else {
            failNextLoad = false
            throw TopazError("TestHistoryAccess.loadDataForTurn")
        }
        var data = try wrapped.loadDataForTurn(turn)
        if stripClientDataOnLoad {
            stripClientDataOnLoad = false
            data[clientName] = nil
            print("TestHistoryAccess: stripped data for '\(clientName)'")
        } else if setClientDataVersionHighOnLoad {
            if let versionedTurnData = data[clientName] {
                data[clientName] = HistoricalTurnData(turnData: versionedTurnData.turnData, version: 100)
                setClientDataVersionHighOnLoad = false
                print("TestHistoryAccess: set version high for '\(clientName)'")
            }
        }
        return data
    }

    var mostRecentTurn: Turn? {
        return wrapped.mostRecentTurn
    }

    var active: Bool {
        get {
            return wrapped.active
        }
        set {
            wrapped.active = newValue
        }
    }
}

/// Test saving + restoring of history
class TestHistorian: TestCase {

    var historical: TestHistorical!

    /// Helper to set up a world with history
    static let turn1Value = 55
    static let turn2Value = 1004
    static let turn3Value = 1230

    private func createTwoTurnWorld() -> TestWorld {
        historical = TestHistorical()
        let world = createDefaultWorld(historicals: [historical])

        // Check history has been reset
        XCTAssertEqual(TestHistorical.INITIAL_STATE_VALUE, historical.state.value)

        historical.state.value = TestHistorian.turn1Value
        world.turn(1)
        historical.state.value = TestHistorian.turn2Value
        world.turn(2)

        return world
    }

    /// Basic save and restore
    func testRewindFfwd() {
        let world = createTwoTurnWorld()
        let secondTurn2Value = 41511

        // Rewind + check
        world.setCurrentTurn(1)
        XCTAssertEqual(2, world.services.turnSource.nextTurn)
        XCTAssertEqual(TestHistorian.turn1Value, historical.state.value)

        // New version of turn 2!
        historical.state.value = secondTurn2Value
        world.turn(2)
        historical.state.value = TestHistorian.turn3Value
        world.turn(3)

        world.setCurrentTurn(2)
        XCTAssertEqual(secondTurn2Value, historical.state.value)

        // Now forward in time
        world.setCurrentTurn(3)
        XCTAssertEqual(TestHistorian.turn3Value, historical.state.value)

        // Check can't go into future that hasn't happened
        doThrow {
            try world.trySetCurrentTurn(400)
            XCTFail("Unexpected changed current turn to 400")
        }
    }

    /// Restore failure, storage failure
    func testRestoreFailure() {
        let world = createTwoTurnWorld()

        historical.failNextRestore = true

        doThrow {
            try world.trySetCurrentTurn(1)
            XCTFail("Unexpected changed current turn to 1")
        }
        XCTAssertFalse(historical.failNextRestore)
    }

    /// Save failure
    func testSaveFailure() {
        let world = createTwoTurnWorld()
        guard let currentAccess = world.services.historian.historyAccess else {
            XCTFail("Confused")
            return
        }
        let historyAccess = TestHistoryAccess(historyAccess: currentAccess)
        world.setHistoryAccess(historyAccess)

        historyAccess.failNextSave = true
        world.turn(3)
        XCTAssertFalse(historyAccess.failNextSave)
        XCTAssertEqual(2, historyAccess.mostRecentTurn)
        XCTAssertEqual(3, world.services.turnSource.thisTurn)
    }

    /// Restore failure, version of storage higher than historical
    func testRestoreFailureVersion() {
        let world = createTwoTurnWorld()

        // history has two turns of data @ version 1, set to support only 0
        historical.historyVersion -= 1

        doThrow {
            try world.trySetCurrentTurn(1)
            XCTFail("Unexpected changed current turn to 1")
        }

        historical.historyVersion += 1
        world.setCurrentTurn(1)
    }

    /// Upgrade
    func testRestoreUpgrade() {
        // save history @ 1
        let world = createTwoTurnWorld()

        // set supported = 0..2
        historical.historyVersion += 1

        // load and convert
        historical.converted = false
        world.setCurrentTurn(1)
        XCTAssertTrue(historical.converted)

        // load again, should not go through conversion again
        historical.converted = false
        world.setCurrentTurn(1)
        XCTAssertFalse(historical.converted)

        historical.historyVersion -= 1
    }

    /// Upgrade no-data-found
    func testRestoreNoDataFound() {
        let world = createTwoTurnWorld()

        guard let currentAccess = world.services.historian.historyAccess else {
            XCTFail("Confused")
            return
        }
        let historyAccess = TestHistoryAccess(historyAccess: currentAccess)
        world.setHistoryAccess(historyAccess)

        // Acceptable no-data-found
        historyAccess.clientName = historical.historyName
        historyAccess.stripClientDataOnLoad = true

        historical.noDataFound = false
        world.setCurrentTurn(1)
        XCTAssertTrue(historical.noDataFound)
        XCTAssertFalse(historyAccess.stripClientDataOnLoad)

        // Unacceptable no-data-found
        historyAccess.clientName = "TurnSource"
        historyAccess.stripClientDataOnLoad = true

        doThrow {
            try world.trySetCurrentTurn(1)
            XCTFail("Unexpectedly restored data OK without TurnSource")
        }
        XCTAssertFalse(historyAccess.stripClientDataOnLoad)

        // While we're here, check unsupported version upgrade
        historyAccess.setClientDataVersionHighOnLoad = true

        doThrow {
            try world.trySetCurrentTurn(1)
            XCTFail("Unexpectedly restored data OK with wrong TurnSource version")
        }
        XCTAssertFalse(historyAccess.setClientDataVersionHighOnLoad)
    }

    /// Silly corner case
    func testTurnRestoreBeforeHistory() {
        let world = TestWorld()
        world.services.turnQueue.sync {
            doThrow {
                try world.services.setCurrentHistoryTurn(22)
            }
        }
    }
}
