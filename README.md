# ios-vibe-memory-test

An iOS app for testing device memory/cache performance, inspired by
[rust-vibe-memory-test](https://github.com/brunoshiroma/rust-vibe-memory-test). The
benchmark itself (sequential read, write, copy, and dependent pointer-chase read
latency) is ported to Swift so it runs natively on iOS, using the same working-set
semantics as the Rust CLI.

## Structure

- `MemoryBenchCore/` — a Swift Package containing the benchmark core logic
  (`runSuite`, `BenchmarkConfig`, `Measurement`, `SizeUnit`, `SizeSelection`) and its
  unit tests. This package builds and its tests run on any platform with Swift
  installed, including Linux:

  ```sh
  cd MemoryBenchCore
  swift test
  ```

- `MemoryVibeTest/` — the iOS app (SwiftUI). Open `MemoryVibeTest/MemoryVibeTest.xcodeproj`
  in Xcode to build and run it on a simulator or device. The app target depends on the
  local `MemoryBenchCore` Swift package.

## Using the app

The app lets you pick one or more working-set sizes to include in a benchmark run,
entering a numeric value together with a unit (`KiB`, `MiB`, or `GiB`), matching the
units accepted by the `rust-vibe-memory-test` CLI's `--sizes` flag. You can add as many
sizes as you like, remove any of them, choose the number of iterations, then run the
benchmark to see per-size throughput (GB/s) and per-element latency (ns/element) for
each operation (read, write, copy, pointer-chase).