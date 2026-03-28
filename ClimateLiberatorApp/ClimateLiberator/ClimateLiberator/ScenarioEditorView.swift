import SwiftUI

private enum ScenarioOutputFormat: String, CaseIterable, Identifiable {
    case asc
    case tif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asc:
            return "ESRI ASCII (.asc)"
        case .tif:
            return "GeoTIFF (.tif)"
        }
    }
}

struct ScenarioEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scenario: ScenarioDefinition
    private let isNewScenario: Bool
    let onSave: (ScenarioDefinition) -> Void

    init(scenario: ScenarioDefinition? = nil, onSave: @escaping (ScenarioDefinition) -> Void) {
        isNewScenario = scenario == nil
        _scenario = State(initialValue: scenario ?? ScenarioDefinition(
            name: "",
            notes: "",
            pathwayLabel: "Green / resilience pathway",
            horizonLabel: "Short-term readiness",
            simulatorCode: "S",
            inputFolder: "",
            outputFolder: "",
            binaryPath: "",
            includeROS: true,
            weatherPeriodMinutes: 60,
            outputFormat: "asc",
            numberOfSimulations: 1,
            numberOfThreads: 1,
            seed: 123,
            tcfdScenarioLabel: "TCFD Scenario"
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scenario") {
                    TextField("Name", text: $scenario.name)
                    TextField("TCFD scenario label", text: $scenario.tcfdScenarioLabel)
                    TextField("Pathway label", text: Binding(
                        get: { scenario.pathwayLabel ?? "" },
                        set: { scenario.pathwayLabel = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Horizon label", text: Binding(
                        get: { scenario.horizonLabel ?? "" },
                        set: { scenario.horizonLabel = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Notes", text: $scenario.notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("Execution") {
                    Picker("Simulator", selection: $scenario.simulatorCode) {
                        Text("Scott & Burgan").tag("S")
                        Text("Kitral").tag("K")
                        Text("FBP-Canada").tag("C")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include ROS", isOn: $scenario.includeROS)
                    TextField("Binary path", text: $scenario.binaryPath)
                    TextField("Input folder", text: $scenario.inputFolder)
                    TextField("Output folder", text: $scenario.outputFolder)
                    TextField("Weather period (minutes)", value: weatherPeriodBinding, format: .number)
                    TextField("Simulations", value: simulationsBinding, format: .number)
                    TextField("Threads", value: threadsBinding, format: .number)
                    TextField("Seed", value: seedBinding, format: .number)
                    Picker("Output format", selection: outputFormatBinding) {
                        ForEach(ScenarioOutputFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                }
            }
            .navigationTitle(isNewScenario ? "New Scenario" : "Scenario Editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        scenario.updatedAt = Date()
                        onSave(scenario)
                        dismiss()
                    }
                    .disabled(scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var weatherPeriodBinding: Binding<Int> {
        Binding(
            get: { scenario.weatherPeriodMinutes },
            set: { scenario.weatherPeriodMinutes = max(1, $0) }
        )
    }

    private var simulationsBinding: Binding<Int> {
        Binding(
            get: { scenario.numberOfSimulations },
            set: { scenario.numberOfSimulations = max(1, $0) }
        )
    }

    private var threadsBinding: Binding<Int> {
        Binding(
            get: { scenario.numberOfThreads },
            set: { scenario.numberOfThreads = max(1, $0) }
        )
    }

    private var seedBinding: Binding<Int> {
        Binding(
            get: { scenario.seed },
            set: { scenario.seed = $0 }
        )
    }

    private var outputFormatBinding: Binding<ScenarioOutputFormat> {
        Binding(
            get: { ScenarioOutputFormat(rawValue: scenario.outputFormat) ?? .asc },
            set: { scenario.outputFormat = $0.rawValue }
        )
    }
}
