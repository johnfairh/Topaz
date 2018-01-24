//
//  TestInMemoryHistoryStore.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
@testable import TopazBase

class TestInMemoryHistoryStore: TestCase, TestHistoryStoreProtocol {

    let debugDumper = DebugDumper { x in print(x) }

    override func setUp() {
        FatalError.debugDumper = debugDumper
    }

    func newStore() -> HistoryStore {
        return InMemoryHistoryStore(debugDumper: debugDumper)
    }

    func testEmptyStore() { tstEmptyStore() }
    func testCreateDelete() { tstCreateDelete() }
}
