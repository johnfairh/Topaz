import XCTest
import Dispatch
import TopazBase

class TopazTests: XCTestCase {

    var stopRunning = false

    func testExample() {
        let services = Services { lm in print(lm) }
        let q = services.turnQueue
        let ts = services.turnSource

        let historyStore = InMemoryHistoryStore(debugDumper: services.debugDumper)
        let history = try! historyStore.createEmpty(name: "TopazTests")
        q.sync {
            try! services.setNewHistory(history)
        }

        ts.register { turn, _ in
            if turn == 4 {
                DispatchQueue.main.async {
                    self.stopRunning = true
                }
            }
        }

        q.sync {
            ts.turn()
        }

        q.sync {
            ts.progress = .automatic(milliseconds: 500)
        }

        while !stopRunning {
            RunLoop.main.run(mode: .defaultRunLoopMode, before: Date.distantFuture)
        }

        services.printDebugString()
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
