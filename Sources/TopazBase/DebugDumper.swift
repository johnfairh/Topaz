//
//  DebugDumper.swift
//  TopazBase
//
//  Distributed under the MIT license, see LICENSE.
//

/// Describe a component that can be dumped
public protocol DebugDumpable: CustomStringConvertible {
    var debugName: String { get }
}

/// Helper to generate multi-line indented debug strings
public final class StringBuilder {
    private var indent: Int
    private var lines: [String]

    /// Get a multi-line string for the added liens
    public var string: String {
        return lines.joined(separator: "\n")
    }

    /// Create a new instance
    public init() {
        indent = 0
        lines = []
    }

    /// Add a line at the current indent.  Do not include a newline.
    public func line(_ str: String) -> StringBuilder {
        lines.append(String(repeating: "  ", count: indent) + str)
        return self
    }

    /// Increase indent by one level
    public func `in`() -> StringBuilder {
        indent += 1
        return self
    }

    /// Decrease indentation by a level.  Silently does nothing if indentation is at the initial state.
    public func out() -> StringBuilder {
        if indent > 0 {
            indent -= 1
        }
        return self
    }
}

/// Generate a human-readable description of the system state.
public final class DebugDumper: CustomStringConvertible {
    private var clients: [DebugDumpable]

    /// Add a client.  Registration order reflected in printout.
    public func register(client: DebugDumpable) {
        clients.append(client)
    }

    /// Create a new instance
    public init() {
        clients = []
    }

    /// Stringify everything
    public var description: String {
        var dump = ""
        clients.forEach { client in
            let prefix = "[\(client.debugName)] "
            let lines = client.description.split(separator: "\n", omittingEmptySubsequences: false)
            dump += lines.map { prefix + $0 }.joined(separator: "\n")
        }
        return dump
    }
}
