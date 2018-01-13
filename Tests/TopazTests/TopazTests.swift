import XCTest
import Dispatch
import TopazBase

class TopazTests: XCTestCase {

    var stopRunning = false

    func testExample() {
        let services = Services { lm in print(lm) }
        let q = services.turnQueue
        let ts = services.turnSource

        ts.register { turn, _ in
            if turn == 10 {
                DispatchQueue.main.async {
                    self.stopRunning = true
                }
            }
        }

        print(ts)

        q.sync {
            ts.turn()
        }

        ts.turn()

        q.sync {
            ts.progress = .automatic(milliseconds: 500)
        }

        print(ts)

        while !stopRunning {
            RunLoop.main.run(mode: .defaultRunLoopMode, before: Date.distantFuture)
        }
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
