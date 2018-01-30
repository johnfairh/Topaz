//
//  ErrorHandling.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

// MARK: - Fatal error hooks

/// Namespace for configuring fatal error behaviour.
/// This drops the multi-instance illusion to avoid passing around
/// generally useless context.
public final class FatalError {
    /// Stash a reference to a debug dumper to get a dump as part of fatal.
    internal static weak var debugDumper: DebugDumper?

    /// Set a function to be called on fatal error after the dump has been collected.
    /// Ideally chain on to the existing value.
    public static var continuation: (String, StaticString, UInt) -> Never = { msg, file, line in
        Swift.fatalError(msg, file: file, line: line)
    }
}

/// Override `Swift.fatalError` to get debug data before exitting.
func fatalError(_ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) -> Never {
    let messageText = message()

    // Push a debug dump to the logger.  All kinds of things could go wrong but ignore that for now.
    FatalError.debugDumper?.dumpForFatal(message: "FatalError \(file):\(line) \(messageText)")

    // Proceed towards death
    FatalError.continuation(messageText, file, line)
}

// MARK: - Exceptions

/// Base class for thrown errors.  Not too sure where I'm going here yet.
public class TopazError: Error, CustomStringConvertible {
    public let underlyingError: Error?
    public let details: String

    public init(underlyingError: Error?, details: String = "") {
        self.underlyingError = underlyingError
        self.details = details

        // Push a debug dump to the logger.  All kinds of things could go wrong but ignore that for now.
        FatalError.debugDumper?.dumpForFatal(message: "exception \(self)")
    }

    public convenience init(_ details: String) {
        self.init(underlyingError: nil, details: details)
    }

    public var description: String {
        return "Exception details:\(details) \(underlyingError as? String ?? "")"
    }
}

extension Logger {
    public func throwError(_ error: TopazError) throws -> Never {
        log(.warning, error.description)
        throw error
    }

    public func throwError(_ details: String) throws -> Never {
        try throwError(TopazError(details))
    }

    public func throwError(underlyingError: Error, details: String = "") throws -> Never {
        try throwError(TopazError(underlyingError: underlyingError, details: details))
    }
}
