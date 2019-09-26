//
//  TestHistoryStore.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import TopazBase

/// A set of tests against the 'historystore' protocol.
protocol TestHistoryStoreProtocol {
    /// Provide just a method to get a new store.
    func newStore() -> HistoryStore
}

/// Tests follow.  Ideally these would be named 'testFoo' and XCTest would just find
/// them in the adopting class.  But, this doesn't work.  So we have to forward.  Sigh.
extension TestHistoryStoreProtocol where Self: TestCase {

    /// Sanity check - new store is empty
    func tstEmptyStore() {
        let store = newStore()
        XCTAssertEqual(0, store.histories.count)
    }

    /// Check create/delete histories
    func tstCreateDelete() {
        let store = newStore()

        doNoThrow {
            let hist1 = try store.createEmpty(name: "Hist1")

            doThrow {
                let hist1a = try store.createEmpty(name: "Hist1")
                XCTFail("Unexpected success creating duplicate history - \(hist1a)")
            }

            let hist2 = try store.createEmpty(name: "Hist2")
            XCTAssertEqual(2, store.histories.count)

            XCTAssertEqual("Hist1", hist1.historyName)
            XCTAssertEqual("Hist2", hist2.historyName)

            XCTAssertFalse(hist1.active)
            XCTAssertNil(hist1.clientData)
            XCTAssertEqual(0..<0, hist1.turns)
            XCTAssertNil(hist1.mostRecentTurn)

            try store.delete(history: hist1)

            doThrow {
                try store.delete(history: hist1)
                XCTFail("Unexpected delete of already-deleted history")
            }

            XCTAssertEqual(1, store.histories.count)

            // Check name available for reuse
            let hist3 = try store.createEmpty(name: "Hist1")
            XCTAssertEqual(2, store.histories.count)

            try store.delete(history: hist2)
            try store.delete(history: hist3)

            XCTAssertEqual(0, store.histories.count)
        }
    }

    /// Check 'active' rule
    func tstDeleteActive() {
        let store = newStore()
        doNoThrow {
            var history = try store.createEmpty(name: "History")
            XCTAssertFalse(history.active)
            history.active = true
            XCTAssertTrue(history.active)
            doThrow {
                try store.delete(history: history)
                XCTFail("Unexpectedly deleted active history")
            }
        }
    }

    /// Check 'getLatestHistory'
    func tstLatestHistory() {
        let store = newStore()
        doNoThrow {
            let history1 = try store.getLatestHistory(newlyNamed: "History1")
            sleep(seconds: 1)
            let history2 = try store.createEmpty(name: "History2")
            XCTAssertEqual("History1", history1.historyName)
            XCTAssertEqual("History2", history2.historyName)

            let history3 = try store.getLatestHistory(newlyNamed: "BadHistory")
            XCTAssertEqual("History2", history3.historyName)
        }
    }

    /// Check save/load of turn data - including date progression
    func tstSaveLoadTurnData() {
        let store = newStore()
        doNoThrow {
            let history = try store.getLatestHistory(newlyNamed: "History")
            XCTAssertNil(history.mostRecentTurn)

            let turn1Data = Data([1,2,3,4])
            let turn2Data = Data([4,5,6,7])
            let version   = HistoryVersion(1)
            let turn1VersionedData = HistoricalTurnData(turnData: turn1Data, version: version)
            let turn2VersionedData = HistoricalTurnData(turnData: turn2Data, version: version)
            let clientName = "Client"
            let turn1AllData = [clientName : turn1VersionedData]
            let turn2AllData = [clientName : turn2VersionedData]

            XCTAssertFalse(areTurnDataSame(a: turn1AllData, b: turn2AllData))

            try history.setDataForTurn(1, data: turn1AllData)
            let turn1Time = history.accessTime

            do {
                let testData = try history.loadDataForTurn(1)
                XCTAssertTrue(areTurnDataSame(a: testData, b: turn1AllData))
            }
            sleep(seconds: 1)
            try history.setDataForTurn(2, data: [clientName : turn2VersionedData])
            let turn2Time = history.accessTime
            XCTAssertTrue(turn2Time > turn1Time)

            do {
                let testData1 = try history.loadDataForTurn(1)
                XCTAssertTrue(areTurnDataSame(a: testData1, b: turn1AllData))
                let testData2 = try history.loadDataForTurn(2)
                XCTAssertTrue(areTurnDataSame(a: testData2, b: turn2AllData))
            }

            XCTAssertEqual(2, history.mostRecentTurn!)
            XCTAssertEqual(1..<3, history.turns)

            doThrow {
                let data = try history.loadDataForTurn(4)
                XCTFail("Unexpectedly loaded data for turn 4: \(data)")
            }
        }
    }
}
