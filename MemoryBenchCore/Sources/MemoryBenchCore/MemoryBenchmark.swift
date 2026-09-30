import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

/// A unit used to express a working-set size when selecting sizes to benchmark.
///
/// Matches the units accepted by the `rust-vibe-memory-test` CLI (`KiB`, `MiB`, `GiB`),
/// using binary (1024-based) multipliers.
public enum SizeUnit: String, CaseIterable, Sendable, Identifiable {
    case bytes = "B"
    case kib = "KiB"
    case mib = "MiB"
    case gib = "GiB"

    public var id: String { rawValue }

    /// Number of bytes represented by one unit of this kind.
    public var bytesPerUnit: Int {
        switch self {
        case .bytes: return 1
        case .kib: return 1024
        case .mib: return 1024 * 1024
        case .gib: return 1024 * 1024 * 1024
        }
    }
}

/// A working-set size selected for benchmarking, expressed as a value plus a unit.
public struct SizeSelection: Identifiable, Hashable, Sendable {
    public var value: Int
    public var unit: SizeUnit

    public init(value: Int, unit: SizeUnit) {
        self.value = value
        self.unit = unit
    }

    public var id: String { "\(value)\(unit.rawValue)" }

    /// The resolved size in bytes, or `nil` if the value/unit combination overflows.
    public var bytes: Int? {
        let (result, overflow) = value.multipliedReportingOverflow(by: unit.bytesPerUnit)
        return overflow ? nil : result
    }

    /// Human readable label, for example "2 MiB".
    public var label: String {
        "\(value) \(unit.rawValue)"
    }
}

/// Configuration for a benchmark run: which working-set sizes (in bytes) to exercise
/// and how many iterations to repeat each operation for.
public struct BenchmarkConfig: Sendable {
    public var sizesBytes: [Int]
    public var iterations: Int

    public init(sizesBytes: [Int], iterations: Int) {
        self.sizesBytes = sizesBytes
        self.iterations = iterations
    }

    public static let `default` = BenchmarkConfig(
        sizesBytes: [
            4 * 1024,
            32 * 1024,
            256 * 1024,
            2 * 1024 * 1024,
            16 * 1024 * 1024,
        ],
        iterations: 20
    )
}

/// The memory operation being measured.
public enum Operation: String, CaseIterable, Sendable {
    case read
    case write
    case copy
    case pointerChase

    public var name: String {
        switch self {
        case .read: return "read"
        case .write: return "write"
        case .copy: return "copy"
        case .pointerChase: return "pointer-chase"
        }
    }
}

/// The result of measuring one operation at one working-set size.
public struct Measurement: Sendable {
    public let operation: Operation
    public let sizeBytes: Int
    public let iterations: Int
    public let elapsedSeconds: Double
    public let bytesPerSecond: Double
    public let nanosecondsPerElement: Double
}

/// Errors that can occur while validating a `BenchmarkConfig`.
public enum BenchmarkError: Error, Equatable, Sendable, CustomStringConvertible {
    case noSizes
    case zeroIterations
    case invalidSize(Int)

    public var description: String {
        switch self {
        case .noSizes:
            return "at least one working-set size is required"
        case .zeroIterations:
            return "iterations must be greater than zero"
        case .invalidSize(let size):
            return "working-set size \(size) must be at least 8 and divisible by 8"
        }
    }
}

private enum Timer {
    static func now() -> Double {
        #if canImport(QuartzCore)
        return CACurrentMediaTime()
        #else
        return Date().timeIntervalSinceReferenceDate
        #endif
    }
}

/// Runs the full benchmark suite (sequential read, write, copy, and pointer-chase)
/// for every configured working-set size.
///
/// This is a direct Swift port of the measurement logic in the `rust-vibe-memory-test`
/// library, so that the same working-set sizes and semantics can be exercised natively
/// on iOS without needing to cross-compile the Rust crate.
public func runSuite(_ config: BenchmarkConfig) throws -> [Measurement] {
    if config.sizesBytes.isEmpty {
        throw BenchmarkError.noSizes
    }
    if config.iterations <= 0 {
        throw BenchmarkError.zeroIterations
    }

    var measurements: [Measurement] = []
    measurements.reserveCapacity(config.sizesBytes.count * 4)

    for sizeBytes in config.sizesBytes {
        if sizeBytes < MemoryLayout<UInt64>.size || sizeBytes % 8 != 0 {
            throw BenchmarkError.invalidSize(sizeBytes)
        }
        let words = sizeBytes / MemoryLayout<UInt64>.size
        var source = [UInt64](repeating: 0, count: words)
        var destination = [UInt64](repeating: 0, count: words)

        for iteration in 0..<config.iterations {
            for index in 0..<words {
                source[index] = UInt64(index) &+ UInt64(iteration)
            }
        }

        // Sequential read
        var start = Timer.now()
        var checksum: UInt64 = 0
        for _ in 0..<config.iterations {
            for value in source {
                checksum = checksum &+ value
            }
        }
        withExtendedLifetime(checksum) {}
        measurements.append(measurement(
            operation: .read,
            sizeBytes: sizeBytes,
            elementsPerIteration: words,
            iterations: config.iterations,
            elapsedSeconds: Timer.now() - start,
            transferredBytesPerIteration: sizeBytes
        ))

        // Sequential write
        start = Timer.now()
        for iteration in 0..<config.iterations {
            for index in 0..<words {
                destination[index] = UInt64(index) &+ UInt64(iteration)
            }
        }
        measurements.append(measurement(
            operation: .write,
            sizeBytes: sizeBytes,
            elementsPerIteration: words,
            iterations: config.iterations,
            elapsedSeconds: Timer.now() - start,
            transferredBytesPerIteration: sizeBytes
        ))

        // Sequential copy
        start = Timer.now()
        for _ in 0..<config.iterations {
            destination = source
        }
        measurements.append(measurement(
            operation: .copy,
            sizeBytes: sizeBytes,
            elementsPerIteration: words,
            iterations: config.iterations,
            elapsedSeconds: Timer.now() - start,
            transferredBytesPerIteration: sizeBytes.multipliedReportingOverflow(by: 2).overflow
                ? Int.max
                : sizeBytes * 2
        ))

        // Dependent pointer-chase read latency
        let next = makePointerChaseRing(length: words)
        start = Timer.now()
        var index = 0
        let totalHops = config.iterations.multipliedReportingOverflow(by: words).overflow
            ? Int.max
            : config.iterations * words
        for _ in 0..<totalHops {
            index = next[index]
        }
        withExtendedLifetime(index) {}
        measurements.append(measurement(
            operation: .pointerChase,
            sizeBytes: sizeBytes,
            elementsPerIteration: words,
            iterations: config.iterations,
            elapsedSeconds: Timer.now() - start,
            transferredBytesPerIteration: sizeBytes
        ))
    }

    return measurements
}

private func measurement(
    operation: Operation,
    sizeBytes: Int,
    elementsPerIteration: Int,
    iterations: Int,
    elapsedSeconds: Double,
    transferredBytesPerIteration: Int
) -> Measurement {
    let elapsed = max(elapsedSeconds, 1e-9)
    let totalElements = elementsPerIteration.multipliedReportingOverflow(by: iterations).overflow
        ? Int.max
        : elementsPerIteration * iterations
    let totalBytes = transferredBytesPerIteration.multipliedReportingOverflow(by: iterations).overflow
        ? Int.max
        : transferredBytesPerIteration * iterations

    return Measurement(
        operation: operation,
        sizeBytes: sizeBytes,
        iterations: iterations,
        elapsedSeconds: elapsed,
        bytesPerSecond: Double(totalBytes) / elapsed,
        nanosecondsPerElement: (elapsed * 1_000_000_000.0) / Double(max(totalElements, 1))
    )
}

/// Builds a random permutation of `0..<length` and returns the "next index" table for
/// a single-cycle pointer chase, matching the xorshift-based shuffle used by the Rust
/// implementation so that every element is visited exactly once per full traversal.
func makePointerChaseRing(length: Int) -> [Int] {
    var order = Array(0..<length)
    var state: UInt64 = 0x9e37_79b9_7f4a_7c15

    if length > 1 {
        for index in stride(from: length - 1, through: 1, by: -1) {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let swapIndex = Int(state % UInt64(index + 1))
            order.swapAt(index, swapIndex)
        }
    }

    var next = [Int](repeating: 0, count: length)
    for pairIndex in 0..<(order.count - 1) {
        next[order[pairIndex]] = order[pairIndex + 1]
    }
    if let last = order.last, let first = order.first {
        next[last] = first
    }
    return next
}
