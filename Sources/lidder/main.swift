import Foundation

// MARK: - Argument parsing

struct Options {
    var once = false
    var raw = false
    var intervalHz = 30.0
}

func parseArguments() -> Options {
    var opts = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--once", "-1":
            opts.once = true
        case "--raw", "-r":
            opts.raw = true
        case "--hz":
            i += 1
            if i < args.count, let v = Double(args[i]), v > 0 {
                opts.intervalHz = min(v, 120)
            } else {
                FileHandle.standardError.write(Data("Error: --hz requires a positive number\n".utf8))
                exit(2)
            }
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write(Data("Unknown option: \(arg)\n".utf8))
            printUsage()
            exit(2)
        }
        i += 1
    }
    return opts
}

func printUsage() {
    let usage = """
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
    print(usage)
}

// MARK: - Serve subcommand

func runServer(_ args: [String]) -> Never {
    var port: UInt16 = 8765
    var hz = 30.0
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--port", "-p":
            i += 1
            if i < args.count, let v = UInt16(args[i]), v > 0 {
                port = v
            } else {
                FileHandle.standardError.write(Data("Error: --port requires a number 1–65535\n".utf8))
                exit(2)
            }
        case "--hz":
            i += 1
            if i < args.count, let v = Double(args[i]), v > 0 {
                hz = min(v, 120)
            } else {
                FileHandle.standardError.write(Data("Error: --hz requires a positive number\n".utf8))
                exit(2)
            }
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write(Data("Unknown serve option: \(args[i])\n".utf8))
            exit(2)
        }
        i += 1
    }

    let sensor: LidAngleSensor
    do {
        sensor = try LidAngleSensor()
        try sensor.open()
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }

    let poller = SensorPoller(sensor: sensor, hz: hz)
    poller.start()

    let server = HTTPServer(poller: poller, port: port)
    do {
        try server.start()
    } catch {
        FileHandle.standardError.write(Data("Failed to start server on port \(port): \(error)\n".utf8))
        exit(1)
    }

    print("Serving lid angle on http://127.0.0.1:\(port)  —  open / for the demo game")
    print("Stream: http://127.0.0.1:\(port)/stream   (Ctrl-C to stop)")

    signal(SIGINT) { _ in exit(0) }
    signal(SIGTERM) { _ in exit(0) }
    dispatchMain()
}

// MARK: - Rendering

func gauge(for angle: Double) -> String {
    // Map 0–180 degrees onto a 30-cell bar.
    let width = 30
    let clamped = max(0, min(180, angle))
    let filled = Int((clamped / 180.0) * Double(width))
    let bar = String(repeating: "█", count: filled)
        + String(repeating: "░", count: width - filled)
    return bar
}

func describe(_ angle: Double) -> String {
    switch angle {
    case ..<5:   return "closed"
    case ..<45:  return "slightly open"
    case ..<90:  return "partially open"
    case ..<120: return "mostly open"
    default:     return "fully open"
    }
}

// MARK: - Main

// Subcommand dispatch: `lidder serve ...` runs the HTTP/SSE backend.
if CommandLine.arguments.dropFirst().first == "serve" {
    runServer(Array(CommandLine.arguments.dropFirst(2)))
}

let options = parseArguments()

let sensor: LidAngleSensor
do {
    sensor = try LidAngleSensor()
    try sensor.open()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

// One-shot mode.
if options.once {
    do {
        let angle = try sensor.readAngle()
        if options.raw {
            print(String(format: "%.1f", angle))
        } else {
            print(String(format: "Lid angle: %.1f° (%@)", angle, describe(angle)))
        }
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

// Live mode.
let isTTY = isatty(STDOUT_FILENO) != 0

// Restore the cursor on exit / interrupt.
func cleanup() {
    if isTTY && !options.raw {
        print("\u{1B}[?25h", terminator: "")  // show cursor
        print("")
    }
    fflush(stdout)
}

signal(SIGINT) { _ in
    cleanup()
    exit(0)
}
signal(SIGTERM) { _ in
    cleanup()
    exit(0)
}

if isTTY && !options.raw {
    print("\u{1B}[?25l", terminator: "")  // hide cursor
    print("Reading lid angle — press Ctrl-C to stop\n")
}

let interval = 1.0 / options.intervalHz
while true {
    do {
        let angle = try sensor.readAngle()
        if options.raw {
            print(String(format: "%.1f", angle))
        } else if isTTY {
            let line = String(
                format: "\r  %6.1f°  [%@]  %@\u{1B}[K",
                angle, gauge(for: angle), describe(angle)
            )
            print(line, terminator: "")
            fflush(stdout)
        } else {
            print(String(format: "%.1f", angle))
        }
    } catch {
        cleanup()
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
    Thread.sleep(forTimeInterval: interval)
}
