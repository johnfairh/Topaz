//
//  TestCase.swift
//  TopazTests
//
//  Distributed under the MIT license, see LICENSE.
//

import XCTest
import TopazBase

/// Common superclass for testcase classes.
class TestCase: XCTestCase {

    /// Sleep the current thread
    func sleep(seconds: UInt) {
        print("TestCase.sleep(\(seconds))")
        Thread.sleep(until: Date().addingTimeInterval(Double(seconds)))
    }

    /// Run some code that could throw but should not
    func doNoThrow(block: () throws -> Void) {
        do {
            try block()
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// Run some code that is expected to throw
    func doThrow(block: () throws -> Void) {
        do {
            try block()
        } catch {
        }
    }

    /// Are two TurnData dictionaries identical?
    func areTurnDataSame(a: [String:HistoricalTurnData], b: [String:HistoricalTurnData]) -> Bool {
        return turnDataSubset(superset: a, supname: "a", subset: b, subname: "b") &&
               turnDataSubset(superset: b, supname: "b", subset: a, subname: "a")
    }

    /// One direction of the 'identical' check
    private func turnDataSubset(superset: [String:HistoricalTurnData], supname: String,
                                subset: [String:HistoricalTurnData], subname: String) -> Bool {
        var isSubset = true
        for key in subset.keys {
            let subTurnData = subset[key]!
            guard let supTurnData = superset[key] else {
                print("Key \(key) is missing from \(supname)")
                isSubset = false
                continue
            }
            guard supTurnData.version == subTurnData.version else {
                print("Version mismatch for \(key), \(supname)=\(supTurnData.version), \(subname)=\(subTurnData.version)")
                isSubset = false
                continue
            }
            guard supTurnData.turnData == subTurnData.turnData else {
                // Might need to spruce this up (decode as string?)
                print("Data mismatch for \(key), \(supname)=\(supTurnData.turnData as NSData), \(subname)=\(subTurnData.turnData as NSData)")
                isSubset = false
                continue
            }
        }
        return isSubset
    }
}
