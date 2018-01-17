//
//  ErrorHandling.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

/// TODO: figure out more, describe stuff
public struct RestoreError: Error {
    public let underlyingError: Error?
    public var details: String

    public init(underlyingError: Error) {
        self.underlyingError = underlyingError
        self.details = ""
    }
    public init(details: String) {
        self.underlyingError = nil
        self.details = details
    }
}

/// fatalError implementation and general crashiness
/// maybe needs DebugDumper first.
