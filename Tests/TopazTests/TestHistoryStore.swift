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

        do {
            let hist1 = try store.createEmpty(name: "Hist1")

            do {
                let hist1a = try store.createEmpty(name: "Hist1")
                XCTFail("Unexpected success creating duplicate history - \(hist1a)")
            } catch {
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

            do {
                try store.delete(history: hist1)
                XCTFail("Unexpected delete of already-deleted history")
            } catch {
            }

            XCTAssertEqual(1, store.histories.count)

            // Check name available for reuse
            let hist3 = try store.createEmpty(name: "Hist1")
            XCTAssertEqual(2, store.histories.count)

            try store.delete(history: hist2)
            try store.delete(history: hist3)

            XCTAssertEqual(0, store.histories.count)
        } catch {
            XCTFail("Unexpected error caught: \(error)")
        }
    }

    /// Check 'active' rule
    func tstDeleteActive() {

    }

    /// Check 'getLatestHistory'
    func tstLatestHistory() {        
    }

    /// Check save/load of turn data - including date progression
    func tstSaveLoadTurnData() {
    }
}
