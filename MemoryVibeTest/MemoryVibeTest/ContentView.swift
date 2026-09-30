import SwiftUI
import MemoryBenchCore

struct ContentView: View {
    @StateObject private var viewModel = BenchmarkViewModel()

    var body: some View {
        NavigationStack {
            Form {
                sizesSection
                iterationsSection
                runSection
                if !viewModel.results.isEmpty {
                    resultsSection
                }
            }
            .navigationTitle("Vibe Memory Test")
        }
    }

    private var sizesSection: some View {
        Section {
            ForEach(viewModel.selections) { selection in
                Text(selection.label)
            }
            .onDelete(perform: viewModel.removeSelections)

            HStack {
                TextField("Valor", value: $viewModel.pendingValue, format: .number)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif

                Picker("Unidade", selection: $viewModel.pendingUnit) {
                    ForEach([SizeUnit.kib, .mib, .gib]) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    viewModel.addPendingSelection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Tamanhos para testar")
        } footer: {
            Text("Selecione um ou mais tamanhos, usando KiB, MiB ou GiB, para incluir no teste de memória.")
        }
    }

    private var iterationsSection: some View {
        Section("Iterações") {
            Stepper("Iterações: \(viewModel.iterations)", value: $viewModel.iterations, in: 1...200)
        }
    }

    private var runSection: some View {
        Section {
            Button {
                Task { await viewModel.run() }
            } label: {
                if viewModel.isRunning {
                    ProgressView()
                } else {
                    Text("Rodar benchmark")
                }
            }
            .disabled(viewModel.isRunning || viewModel.selections.isEmpty)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var resultsSection: some View {
        Section("Resultados") {
            ForEach(viewModel.results) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.sizeLabel)
                        .font(.headline)
                    ForEach(Array(group.measurements.enumerated()), id: \.offset) { _, measurement in
                        HStack {
                            Text(measurement.operation.name)
                                .frame(width: 100, alignment: .leading)
                            Spacer()
                            Text(MeasurementFormatting.gigabytesPerSecond(measurement))
                            Spacer()
                            Text(MeasurementFormatting.nanosecondsPerElement(measurement))
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    ContentView()
}
