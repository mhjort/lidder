import Testing
@testable import LidderCore

@Suite struct ArgumentsTests {

    @Test func noArgumentsMeansLiveDisplay() throws {
        #expect(try parseCommand([]) == .display(DisplayOptions()))
    }

    @Test func displayFlags() throws {
        #expect(try parseCommand(["--once", "--raw", "--hz", "60"])
                == .display(DisplayOptions(once: true, raw: true, hz: 60)))
        #expect(try parseCommand(["-1", "-r"])
                == .display(DisplayOptions(once: true, raw: true)))
    }

    @Test func hzIsClampedToMax() throws {
        #expect(try parseCommand(["--hz", "500"]) == .display(DisplayOptions(hz: 120)))
        #expect(try parseCommand(["serve", "--hz", "500"]) == .serve(ServeOptions(hz: 120)))
    }

    @Test(arguments: [["--hz"], ["--hz", "0"], ["--hz", "-5"], ["--hz", "fast"]])
    func invalidHzIsRejected(args: [String]) {
        #expect(throws: UsageError(message: "Error: --hz requires a positive number", showUsage: false)) {
            try parseCommand(args)
        }
    }

    @Test func unknownDisplayOptionShowsUsage() {
        #expect(throws: UsageError(message: "Unknown option: --bogus", showUsage: true)) {
            try parseCommand(["--bogus"])
        }
    }

    @Test func help() throws {
        #expect(try parseCommand(["--help"]) == .help)
        #expect(try parseCommand(["-h"]) == .help)
        #expect(try parseCommand(["serve", "--help"]) == .help)
    }

    @Test func serveDefaults() throws {
        #expect(try parseCommand(["serve"]) == .serve(ServeOptions(port: 8765, hz: 30)))
    }

    @Test func serveOptions() throws {
        #expect(try parseCommand(["serve", "--port", "9000", "--hz", "60"])
                == .serve(ServeOptions(port: 9000, hz: 60)))
        #expect(try parseCommand(["serve", "-p", "9001"]) == .serve(ServeOptions(port: 9001)))
    }

    @Test(arguments: [["serve", "--port"], ["serve", "--port", "0"],
                      ["serve", "--port", "70000"], ["serve", "--port", "http"]])
    func invalidPortIsRejected(args: [String]) {
        #expect(throws: UsageError(message: "Error: --port requires a number 1–65535", showUsage: false)) {
            try parseCommand(args)
        }
    }

    @Test func unknownServeOption() {
        #expect(throws: UsageError(message: "Unknown serve option: --once", showUsage: false)) {
            try parseCommand(["serve", "--once"])
        }
    }

    @Test func serveIsOnlyASubcommandInFirstPosition() {
        #expect(throws: UsageError.self) {
            try parseCommand(["--raw", "serve"])
        }
    }
}
