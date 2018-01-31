//
//  TestErrors.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import TopazBase

class TestComponent: Logger {
    var logMessageHandler: LogMessage.Handler

    init(debugDumper: DebugDumper) {
        self.logMessageHandler = debugDumper.logMessageHandler
    }

    struct NativeError: Error {}

    private func throwNativeError() throws {
        throw NativeError()
    }

    func testWrappedError() throws {
        do {
            try throwNativeError()
        } catch {
            try throwError(underlyingError: error)
        }
    }
}

class TestErrors: TestCase {
    /// Error-throwing helpers
    func testThrow() {
        let world = TestWorld()
        let component = TestComponent(debugDumper: world.services.debugDumper)
        do {
            try component.testWrappedError()
            XCTFail("Should have thrown an error")
        } catch {
            print("Caught \(error)")
        }
    }

    /// FatalError helpers.  This is mondo suspect because it leaves a thread (+world) just pinned forever.
    /// We can't unwind from fatal() even in this simple test scenario because of the -> Never typing.
    func testFatal() {
        let world = TestWorld()
        let component = TestComponent(debugDumper: world.services.debugDumper)

        let fatalExpectation = expectation(description: "Fatal error happened")

        let oldContinuation = FatalError.continuation

        FatalError.continuation = { msg, file, line in
            fatalExpectation.fulfill()
            print("TestCase FatalError handler, hanging thread")
            FatalError.continuation = oldContinuation
            while true {
                RunLoop.current.run() // hmm this isn't -> Never...
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.checkTurnQueue(component)
        }
        waitForExpectations(timeout: 10)
    }

    /// LogMessage helpers
    func testLogLevel() {
        func check(_ level: LogLevel, _ debug: Bool) {
            XCTAssertEqual(debug, level.isDebug)
        }
        check(.error, false)
        check(.warning, false)
        check(.info, false)
        check(.debug, true)
        check(.debugHistory, true)
    }
}
