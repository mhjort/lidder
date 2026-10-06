import Foundation

// MARK: - Commands

public struct DisplayOptions: Equatable {
    public var once = false
    public var raw = false
    public var hz = 30.0

    public init(once: Bool = false, raw: Bool = false, hz: Double = 30.0) {
        self.once = once
        self.raw = raw
        self.hz = hz
    }
}

public struct ServeOptions: Equatable {
    public var port: UInt16 = 8765
    public var hz = 30.0

    public init(port: UInt16 = 8765, hz: Double = 30.0) {
        self.port = port
        self.hz = hz
    }
}

public enum Command: Equatable {
    case display(DisplayOptions)
    case serve(ServeOptions)
    case help
}

public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let message: String
    /// Whether the full usage text should be printed after the message.
    public let showUsage: Bool

    public var description: String { message }
}

/// Highest accepted `--hz` value; larger values are clamped to this.
let maxHz = 120.0

// MARK: - Parsing

/// Parses the arguments that follow the executable name.
public func parseCommand(_ args: [String]) throws -> Command {
    if args.first == "serve" {
        return try parseServe(Array(args.dropFirst()))
    }
    return try parseDisplay(args)
}

private func parseDisplay(_ args: [String]) throws -> Command {
    var opts = DisplayOptions()
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--once", "-1":
            opts.once = true
        case "--raw", "-r":
            opts.raw = true
        case "--hz":
            i += 1
            opts.hz = try parseHz(args, at: i)
        case "--help", "-h":
            return .help
        default:
            throw UsageError(message: "Unknown option: \(args[i])", showUsage: true)
        }
        i += 1
    }
    return .display(opts)
}

private func parseServe(_ args: [String]) throws -> Command {
    var opts = ServeOptions()
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--port", "-p":
            i += 1
            guard i < args.count, let v = UInt16(args[i]), v > 0 else {
                throw UsageError(message: "Error: --port requires a number 1–65535", showUsage: false)
            }
            opts.port = v
        case "--hz":
            i += 1
            opts.hz = try parseHz(args, at: i)
        case "--help", "-h":
            return .help
        default:
            throw UsageError(message: "Unknown serve option: \(args[i])", showUsage: false)
        }
        i += 1
    }
    return .serve(opts)
}

private func parseHz(_ args: [String], at i: Int) throws -> Double {
    guard i < args.count, let v = Double(args[i]), v > 0 else {
        throw UsageError(message: "Error: --hz requires a positive number", showUsage: false)
    }
    return min(v, maxHz)
}

// MARK: - Usage

public let usageText = """
lidder — read the MacBook lid angle

USAGE:
    lidder [OPTIONS]          Show the lid angle live in the terminal
    lidder serve [OPTIONS]    Serve the lid angle over HTTP/SSE for a browser

DISPLAY OPTIONS:
    -1, --once     Print the angle once and exit
    -r, --raw      Print only the numeric angle (good for scripting)
    --hz <n>       Refresh rate in Hz for live mode (default 30, max 120)
    -h, --help     Show this help

SERVE OPTIONS:
    --port <n>     TCP port to listen on (default 8765)
    --hz <n>       Sensor sample rate in Hz (default 30, max 120)

    Endpoints (bound to 127.0.0.1 only):
      GET /stream  Server-Sent Events: data: {"angle","velocity","ts"}
      GET /angle   Latest sample as JSON
      GET /health  {"ok":true}
      GET /        Built-in demo game

Reads the Apple lid angle HID sensor. Requires a MacBook with a
lid angle sensor (recent Apple Silicon models).
"""
