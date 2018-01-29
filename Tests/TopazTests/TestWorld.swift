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

    /// Helper to change the current turn
    func setCurrentTurn(_ turn: Turn) {
        do {
            try services.turnQueue.sync {
                try services.setCurrentHistoryTurn(turn)
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// Apparatus to run main loop / asynchronously stop it
    private var stopRunningMainLoop: Bool

    func runMainLoop() {
        stopRunningMainLoop = false
        while !stopRunningMainLoop {
            RunLoop.main.run(mode: .defaultRunLoopMode, before: Date.distantFuture)
        }
    }

    /// Schedule the main loop to stop soon
    func stopMainLoopAsync() {
        DispatchQueue.main.async {
            self.stopRunningMainLoop = true
        }
    }
}
