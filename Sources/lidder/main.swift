import Foundation
import LidderCore

// MARK: - Argument parsing

let command: Command
do {
    command = try parseCommand(Array(CommandLine.arguments.dropFirst()))
} catch let error as UsageError {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    if error.showUsage {
        print(usageText)
    }
    exit(2)
}

func openSensor() -> LidAngleSensor {
    do {
        let sensor = try LidAngleSensor()
        try sensor.open()
        return sensor
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

// MARK: - Serve subcommand

func runServer(_ opts: ServeOptions) -> Never {
    let poller = SensorPoller(sensor: openSensor(), hz: opts.hz)
    poller.start()

    let server = HTTPServer(poller: poller, port: opts.port)
    do {
        try server.start()
    } catch {
        FileHandle.standardError.write(Data("Failed to start server on port \(opts.port): \(error)\n".utf8))
        exit(1)
    }

    print("Serving lid angle on http://127.0.0.1:\(opts.port)  —  open / for the demo game")
    print("Stream: http://127.0.0.1:\(opts.port)/stream   (Ctrl-C to stop)")

    signal(SIGINT) { _ in exit(0) }
    signal(SIGTERM) { _ in exit(0) }
    dispatchMain()
}

// MARK: - Main

let options: DisplayOptions
switch command {
case .help:
    print(usageText)
    exit(0)
case .serve(let opts):
    runServer(opts)
case .display(let opts):
    options = opts
}

let sensor = openSensor()

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

let interval = 1.0 / options.hz
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
