import Foundation
import SwiftUI
import Combine

final class ScenarioLibraryStore: ObservableObject {
    @Published private(set) var scenarios: [ScenarioDefinition] = []
    @Published var selectedScenarioID: ScenarioDefinition.ID?
    @Published var governanceMetadata: GovernanceMetadata
    @Published var targetBands: [TargetBand] = []

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? ScenarioLibraryStore.defaultStorageURL()
        self.governanceMetadata = GovernanceMetadata(
            boardOwner: "",
            managementOwner: "",
            approvalStatus: "Draft",
            reviewDate: nil,
            riskAppetiteNotes: "",
            delegatedAuthorityNotes: ""
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    var selectedScenario: ScenarioDefinition? {
        scenarios.first { $0.id == selectedScenarioID }
    }

    func addScenario(_ scenario: ScenarioDefinition) {
        scenarios.append(scenario)
        selectedScenarioID = scenario.id
        persist()
    }

    func updateScenario(_ scenario: ScenarioDefinition) {
        guard let index = scenarios.firstIndex(where: { $0.id == scenario.id }) else { return }
        var updated = scenario
        updated.updatedAt = Date()
        scenarios[index] = updated
        persist()
    }

    func deleteScenario(id: ScenarioDefinition.ID) {
        scenarios.removeAll { $0.id == id }
        if selectedScenarioID == id {
            selectedScenarioID = scenarios.first?.id
        }
        persist()
    }

    func selectScenario(id: ScenarioDefinition.ID?) {
        selectedScenarioID = id
        persist()
    }

    func upsertTargetBand(_ band: TargetBand) {
        if let index = targetBands.firstIndex(where: { $0.id == band.id }) {
            targetBands[index] = band
        } else {
            targetBands.append(band)
        }
        persist()
    }

    func deleteTargetBand(id: TargetBand.ID) {
        targetBands.removeAll { $0.id == id }
        persist()
    }

    func updateGovernanceMetadata(_ metadata: GovernanceMetadata) {
        governanceMetadata = metadata
        persist()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            if scenarios.isEmpty {
                scenarios = ScenarioLibraryStore.defaultScenarios()
                selectedScenarioID = scenarios.first?.id
            }
            return
        }

        do {
            let snapshot = try decoder.decode(ScenarioLibrarySnapshot.self, from: data)
            scenarios = snapshot.scenarios
            selectedScenarioID = snapshot.selectedScenarioID
            governanceMetadata = snapshot.governanceMetadata
            targetBands = snapshot.targetBands
        } catch {
            if scenarios.isEmpty {
                scenarios = ScenarioLibraryStore.defaultScenarios()
                selectedScenarioID = scenarios.first?.id
            }
        }

        if selectedScenarioID == nil {
            selectedScenarioID = scenarios.first?.id
        }
    }

    func persist() {
        let snapshot = ScenarioLibrarySnapshot(
            scenarios: scenarios,
            selectedScenarioID: selectedScenarioID,
            governanceMetadata: governanceMetadata,
            targetBands: targetBands,
            updatedAt: Date()
        )

        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Persistence is best-effort; keep the in-memory store usable.
        }
    }

    static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("ClimateLiberator/TCFD/scenarios.json")
    }

    static func defaultScenarios() -> [ScenarioDefinition] {
        [
            ScenarioDefinition(
                name: "Board-ready baseline",
                notes: "Baseline wildfire assessment for governance and pilot reporting.",
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
                tcfdScenarioLabel: "TCFD Baseline"
            ),
            ScenarioDefinition(
                name: "High-wind stress test",
                notes: "Higher thread count and repeated simulation run for resilience review.",
                pathwayLabel: "Stress / high-impact pathway",
                horizonLabel: "Medium-term stress test",
                simulatorCode: "S",
                inputFolder: "",
                outputFolder: "",
                binaryPath: "",
                includeROS: true,
                weatherPeriodMinutes: 60,
                outputFormat: "asc",
                numberOfSimulations: 5,
                numberOfThreads: 4,
                seed: 123,
                tcfdScenarioLabel: "TCFD Stress Test"
            )
        ]
    }
}
