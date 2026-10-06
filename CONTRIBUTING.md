# Contributing to lidder

Thanks for your interest! Bug reports, ideas and pull requests are all welcome.

## Reporting problems

The lid angle sensor differs between MacBook models, so please include your
Mac model, macOS version and the output of `lidder --once` when you
[open an issue](https://github.com/mhjort/lidder/issues/new/choose).

## Development

You need macOS 13 or later and Xcode 16 or later.

```sh
swift build      # build
swift test       # run the tests
swift run lidder # run against your own MacBook's sensor
```

The code is split into two targets:

- `Sources/LidderCore`: everything that can be tested: argument parsing, the
  HTTP router, velocity smoothing, sensor report decoding and the terminal gauge,
  plus the IOKit sensor access, the poller and the network server.
- `Sources/lidder`: `main.swift`, which wires those together into the CLI.

The tests don't need a lid angle sensor, so they also run on CI. If your change
touches the sensor, the CLI output or the HTTP server, please also try it on a
real MacBook and mention the model in the pull request.

### Tests fail with "plugin for module 'TestingMacros' not found"

This happens with the Command Line Tools instead of Xcode. Either switch to Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

or point the compiler at the plugin directly:

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## Pull requests

- Keep each pull request focused on one change.
- Add or update tests for behavior changes.
- Make sure CI is green.

By contributing you agree that your contribution is licensed under the
[MIT License](LICENSE).
