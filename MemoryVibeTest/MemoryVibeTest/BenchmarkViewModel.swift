import Foundation
import MemoryBenchCore

/// Rows produced after a benchmark run, grouped for display: one working-set size
/// with a measurement for each operation (read, write, copy, pointer-chase).
struct BenchmarkResultGroup: Identifiable {
    let id: Int
    let sizeLabel: String
    let measurements: [Measurement]
}

@MainActor
final class BenchmarkViewModel: ObservableObject {
    /// Sizes the user has picked to include in the next run.
    @Published var selections: [SizeSelection] = [
        SizeSelection(value: 32, unit: .kib),
        SizeSelection(value: 2, unit: .mib),
        SizeSelection(value: 16, unit: .mib),
    ]

    /// Pending value/unit used by the "add size" control.
    @Published var pendingValue: Int = 4
    @Published var pendingUnit: SizeUnit = .kib

    @Published var iterations: Int = 20
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var results: [BenchmarkResultGroup] = []

    func addPendingSelection() {
        guard pendingValue > 0 else { return }
        let selection = SizeSelection(value: pendingValue, unit: pendingUnit)
        guard !selections.contains(selection) else { return }
        selections.append(selection)
    }

    func removeSelections(at offsets: IndexSet) {
        selections.remove(atOffsets: offsets)
    }

    func run() async {
        errorMessage = nil
        results = []

        guard !selections.isEmpty else {
            errorMessage = "Selecione ao menos um tamanho para testar."
            return
        }

        var sizesBytes: [Int] = []
        for selection in selections {
            guard let bytes = selection.bytes else {
                errorMessage = "O tamanho \(selection.label) é grande demais."
                return
            }
            sizesBytes.append(bytes)
        }

        let config = BenchmarkConfig(sizesBytes: sizesBytes, iterations: iterations)
        isRunning = true
        defer { isRunning = false }

        do {
            let measurements = try await Task.detached(priority: .userInitiated) {
                try runSuite(config)
            }.value

            results = Self.group(measurements: measurements, selections: selections)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private static func group(measurements: [Measurement], selections: [SizeSelection]) -> [BenchmarkResultGroup] {
        let perSize = Operation.allCases.count
        return selections.enumerated().map { index, selection in
            let start = index * perSize
            let end = min(start + perSize, measurements.count)
            let slice = start < end ? Array(measurements[start..<end]) : []
            return BenchmarkResultGroup(id: index, sizeLabel: selection.label, measurements: slice)
        }
    }
}

enum MeasurementFormatting {
    static func gigabytesPerSecond(_ measurement: Measurement) -> String {
        String(format: "%.2f GB/s", measurement.bytesPerSecond / 1_000_000_000.0)
    }

    static func nanosecondsPerElement(_ measurement: Measurement) -> String {
        String(format: "%.2f ns/elem", measurement.nanosecondsPerElement)
    }
}
