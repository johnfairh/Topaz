//
//  ErrorHandling.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

// MARK: - Fatal error hooks

/// Namespace for configuring fatal error behaviour
public final class FatalError {
    /// Stash a reference to a debug dumper to get a dump as part of fatal.
    internal static weak var debugDumper: DebugDumper?

    /// Set a function to be called on fatal error after the dump has been collected.
    /// If nil then `Swift.fatalError(...)` is called and the process exits.
    public static var continuation: (( () -> String, StaticString, UInt ) -> Never)?
}

/// Override `Swift.fatalError` to get debug data before exitting.
func fatalError(_ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) -> Never {

    // Push a debug dump to the logger.  All kinds of things could go wrong but ignore that for now.
    FatalError.debugDumper.map { $0.dumpForFatal(message: "fatalError \(message()) file: \(file) line: \(line)") }

    // Proceed towards
    if let continuation = FatalError.continuation {
        continuation(message, file, line)
    } else {
        Swift.fatalError(message, file: file, line: line)
    }
}

// MARK: - Exceptions

/// Base class for thrown errors.  Not too sure where I'm going here yet.
public class TopazError: Error, CustomStringConvertible {
    public let underlyingError: Error?
    public let details: String

    public init(underlyingError: Error?, details: String) {
        self.underlyingError = underlyingError
        self.details = details

        // Push a debug dump to the logger.  All kinds of things could go wrong but ignore that for now.
        FatalError.debugDumper.map { $0.dumpForFatal(message: "exception \(self)") }
    }

    public convenience init(underlyingError: Error) {
        self.init(underlyingError: underlyingError, details: "")
    }

    public convenience init(_ details: String) {
        self.init(underlyingError: nil, details: details)
    }

    public var description: String {
        return "Exception details:\(details) \(underlyingError as? String ?? "(no underlying error)")"
    }
}

/// temp compat patch
typealias RestoreError = TopazError
