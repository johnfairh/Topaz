//
//  TestWorld.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import Foundation
import TopazBase

/// Wrap up the bundle of stuff required for a world test
class TestWorld {

    var services: Services

    var historyStore: InMemoryHistoryStore

    init() {
        services = Services { lm in
            let timestamp = Date().description
            print("\(timestamp) \(lm.body())")
        }
        historyStore = InMemoryHistoryStore(debugDumper: services.debugDumper)
        stopRunningMainLoop = false
    }

    /// Helper to do 'default' things to pick history
    func setDefaultHistory() throws {
        let history = try historyStore.getLatestHistory(newlyNamed: "TstHistory")
        try services.turnQueue.sync {
            try services.setNewHistory(history)
        }
    }

    /// Helper to run a single turn - require the turn number to help docs in client
    func turn(_ turn: Turn) {
        services.turnQueue.sync {
            XCTAssertEqual(turn, services.turnSource.nextTurn)
            services.turnSource.turn()
        }
    }

    /// Helper to change the current turn - work or fail test
    func setCurrentTurn(_ turn: Turn) {
        do {
            try trySetCurrentTurn(turn)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// Helper to change the current turn - can throw
    func trySetCurrentTurn(_ turn: Turn) throws {
        try services.turnQueue.sync {
            try services.setCurrentHistoryTurn(turn)
        }
    }

    /// Helper to replace the history
    func setHistoryAccess(_ historyAccess: HistoryAccess) {
        services.turnQueue.sync {
            do {
                try services.setNewHistory(historyAccess)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    /// Helper to schedule timers
    func scheduleTimer(after: TurnCount, callback: @escaping () -> Void) -> TurnTimerToken {
        return services.turnQueue.sync {
            services.turnTimer.schedule(after: after, callback: callback)
        }
    }

    /// Helper to schedule repeating timer
    func scheduleTimer(after: TurnCount, repeatingEvery: TurnCount, callback: @escaping () -> Void) -> TurnTimerToken {
        return services.turnQueue.sync {
            services.turnTimer.schedule(after: after, repeatingEvery: repeatingEvery, callback: callback)
        }
    }

    /// Apparatus to run main loop / asynchronously stop it
    private var stopRunningMainLoop: Bool

    func runMainLoop() {
        stopRunningMainLoop = false
        while !stopRunningMainLoop {
            RunLoop.main.run(mode: .default, before: Date.distantFuture)
        }
    }

    /// Schedule the main loop to stop soon
    func stopMainLoopAsync() {
        DispatchQueue.main.async {
            self.stopRunningMainLoop = true
        }
    }
}
