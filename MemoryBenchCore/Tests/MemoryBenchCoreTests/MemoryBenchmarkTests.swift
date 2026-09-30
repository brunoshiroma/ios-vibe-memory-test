import XCTest
@testable import MemoryBenchCore

final class MemoryBenchmarkTests: XCTestCase {
    func testSuiteMeasuresAllOperationsForEachSize() throws {
        let results = try runSuite(BenchmarkConfig(sizesBytes: [8, 64], iterations: 2))

        XCTAssertEqual(results.count, 8)
        XCTAssertEqual(
            results.map(\.operation),
            [
                .read, .write, .copy, .pointerChase,
                .read, .write, .copy, .pointerChase,
            ]
        )
        XCTAssertTrue(results.allSatisfy { $0.bytesPerSecond.isFinite })
    }

    func testRejectsEmptyAndInvalidConfigurations() {
        XCTAssertThrowsError(try runSuite(BenchmarkConfig(sizesBytes: [], iterations: 1))) { error in
            XCTAssertEqual(error as? BenchmarkError, .noSizes)
        }
        XCTAssertThrowsError(try runSuite(BenchmarkConfig(sizesBytes: [16], iterations: 0))) { error in
            XCTAssertEqual(error as? BenchmarkError, .zeroIterations)
        }
        XCTAssertThrowsError(try runSuite(BenchmarkConfig(sizesBytes: [7], iterations: 1))) { error in
            XCTAssertEqual(error as? BenchmarkError, .invalidSize(7))
        }
    }

    func testPointerChaseRingVisitsEveryEntryOnce() {
        let ring = makePointerChaseRing(length: 17)
        var visited = [Bool](repeating: false, count: ring.count)
        var index = 0

        for _ in 0..<ring.count {
            XCTAssertFalse(visited[index], "index \(index) visited twice")
            visited[index] = true
            index = ring[index]
        }

        XCTAssertEqual(index, 0, "ring should form a single cycle back to the start")
        XCTAssertTrue(visited.allSatisfy { $0 })
    }

    func testPointerChaseRingHandlesSingleElement() {
        let ring = makePointerChaseRing(length: 1)
        XCTAssertEqual(ring, [0])
    }

    func testSizeSelectionComputesBytesForEachUnit() {
        XCTAssertEqual(SizeSelection(value: 4, unit: .kib).bytes, 4 * 1024)
        XCTAssertEqual(SizeSelection(value: 16, unit: .mib).bytes, 16 * 1024 * 1024)
        XCTAssertEqual(SizeSelection(value: 1, unit: .gib).bytes, 1024 * 1024 * 1024)
        XCTAssertEqual(SizeSelection(value: 512, unit: .bytes).bytes, 512)
    }

    func testSizeSelectionLabelIncludesUnit() {
        XCTAssertEqual(SizeSelection(value: 2, unit: .mib).label, "2 MiB")
    }

    func testBenchmarkConfigDefaultMatchesCliDefaults() {
        XCTAssertEqual(
            BenchmarkConfig.default.sizesBytes,
            [4 * 1024, 32 * 1024, 256 * 1024, 2 * 1024 * 1024, 16 * 1024 * 1024]
        )
        XCTAssertEqual(BenchmarkConfig.default.iterations, 20)
    }
}
