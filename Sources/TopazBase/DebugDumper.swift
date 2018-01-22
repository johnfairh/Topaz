//
//  DebugDumper.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

import Foundation

/// Describe a component that can be dumped
public protocol DebugDumpable: CustomStringConvertible {
    var debugName: String { get }
}

/// Helper to generate multi-line indented debug strings
public final class StringBuilder {
    private var indent: Int
    private var lines: [String]

    /// Get a multi-line string for the added lines
    public var string: String {
        return lines.joined(separator: "\n")
    }

    /// Create a new instance
    public init() {
        indent = 0
        lines = []
    }

    /// Add a line at the current indent.  Do not include a newline.
    @discardableResult
    public func line(_ str: String) -> StringBuilder {
        lines.append(String(repeating: "  ", count: indent) + str)
        return self
    }

    /// Increase indent by one level
    @discardableResult
    public func `in`() -> StringBuilder {
        indent += 1
        return self
    }

    /// Decrease indentation by a level.  Silently does nothing if indentation is at the initial state.
    @discardableResult
    public func out() -> StringBuilder {
        if indent > 0 {
            indent -= 1
        }
        return self
    }
}

/// Generate a human-readable description of the system state.
public final class DebugDumper: CustomStringConvertible {
    /// Store the system log handler, other services get it from here.
    public let logMessageHandler: LogMessage.Handler

    private var clients: [DebugDumpable]

    /// Add a client.  Registration order reflected in printout.
    public func register(debugDumpable client: DebugDumpable) {
        clients.append(client)
    }

    /// Create a new instance
    public init(logMessageHandler: @escaping LogMessage.Handler) {
        self.logMessageHandler = logMessageHandler
        clients = []
    }

    static private let dashes = String(repeating: "-", count: 100)

    /// Stringify everything
    public var description: String {
        let builder = StringBuilder()
        let timestamp = Date().description
        builder.line(DebugDumper.dashes)
            .line("Start DebugDump at \(timestamp)")
            .line(DebugDumper.dashes)
        clients.forEach { client in
            let prefix = "[\(client.debugName)] "
            let lines = client.description.split(separator: "\n", omittingEmptySubsequences: false)
            builder.line(lines.map { prefix + $0 }.joined(separator: "\n"))
        }
        builder.line(DebugDumper.dashes)
            .line("End DebugDump at \(timestamp)")
            .line(DebugDumper.dashes)
        return builder.string
    }

    /// Send the debug dump as a log message
    public func log(_ level: LogLevel = .debug) {
        logMessageHandler(LogMessage(level) { self.description })
    }
}
