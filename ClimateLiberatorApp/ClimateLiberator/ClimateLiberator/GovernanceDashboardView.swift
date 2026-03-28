import SwiftUI

struct GovernanceDashboardView: View {
    @StateObject private var scenarioStore: ScenarioLibraryStore
    @StateObject private var reviewStore: TCFDReviewStore
    @State private var showingScenarioEditor = false
    @State private var editingScenario: ScenarioDefinition?
    @State private var governanceDraft: GovernanceMetadata
    @Environment(\.dismiss) private var dismiss

    init(scenarioStore: ScenarioLibraryStore,
         reviewStore: TCFDReviewStore) {
        _scenarioStore = StateObject(wrappedValue: scenarioStore)
        _reviewStore = StateObject(wrappedValue: reviewStore)
        _governanceDraft = State(initialValue: scenarioStore.governanceMetadata)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    scenariosCard
                    governanceCard
                    reviewCard
                    targetBandsCard
                }
                .padding()
            }
            .navigationTitle("Governance Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh Bundles") {
                        reviewStore.refreshFromDisk()
                    }
                }
            }
        }
        .sheet(isPresented: $showingScenarioEditor) {
            ScenarioEditorView(scenario: editingScenario) { scenario in
                if scenarioStore.scenarios.contains(where: { $0.id == scenario.id }) {
                    scenarioStore.updateScenario(scenario)
                } else {
                    scenarioStore.addScenario(scenario)
                }
                editingScenario = nil
            }
        }
        .onChange(of: scenarioStore.governanceMetadata) { _, newValue in
            governanceDraft = newValue
        }
    }

    private var headerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("TCFD Review Workspace")
                    .font(.title2.bold())
                Text("Manage scenario presets, board metadata, and the persisted wildfire disclosure bundles created after successful runs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scenariosCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Scenario Library")
                        .font(.headline)
                    Spacer()
                    Button("Add Scenario") {
                        editingScenario = nil
                        showingScenarioEditor = true
                    }
                }

                if scenarioStore.scenarios.isEmpty {
                    Text("No saved scenarios yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scenarioStore.scenarios) { scenario in
                        scenarioRow(for: scenario)
                    }
                }
            }
        }
    }

    private var governanceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Governance Metadata")
                    .font(.headline)
                GovernanceMetadataEditor(metadata: $governanceDraft) {
                    scenarioStore.updateGovernanceMetadata(governanceDraft)
                }
            }
        }
    }

    private var reviewCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Persisted Run Bundles")
                        .font(.headline)
                    Spacer()
                    Button("Reload") {
                        reviewStore.reload()
                    }
                }

                if reviewStore.bundles.isEmpty {
                    Text("No persisted TCFD bundles found. Run Phase 1 output generation first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reviewStore.bundles) { bundle in
                        bundleRow(for: bundle)
                    }
                    if let selected = reviewStore.selectedBundle {
                        bundleDetail(for: selected)
                    }
                }
            }
        }
    }

    private var targetBandsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Target Bands")
                        .font(.headline)
                    Spacer()
                    Button("Add Target") {
                        let band = TargetBand(metricName: "Burn probability", thresholdValue: 5.0, unit: "%", comparison: .lessThanOrEqual, notes: "Example target band")
                        scenarioStore.upsertTargetBand(band)
                    }
                }

                if scenarioStore.targetBands.isEmpty {
                    Text("No target bands configured yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scenarioStore.targetBands) { band in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(band.metricName)
                                .font(.subheadline.bold())
                            Text("\(band.comparison.displayName) \(band.thresholdValue, specifier: "%.2f") \(band.unit)")
                                .foregroundStyle(.secondary)
                            if !band.notes.isEmpty {
                                Text(band.notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func scenarioRow(for scenario: ScenarioDefinition) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.name)
                    .font(.subheadline.bold())
                Text("\(scenario.tcfdScenarioLabel) • \(scenario.simulatorCode) • \(scenario.numberOfSimulations)x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !scenario.notes.isEmpty {
                    Text(scenario.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button("Edit") {
                    editingScenario = scenario
                    showingScenarioEditor = true
                }
                Button("Use") {
                    scenarioStore.selectScenario(id: scenario.id)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private func bundleRow(for bundle: TCFDRunArtifactBundle) -> some View {
        Button {
            reviewStore.selectBundle(id: bundle.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle.simulatorLabel)
                        .font(.subheadline.bold())
                    Text(bundle.timestamp, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(bundle.totalBurntPercent.map { String(format: "%.1f%%", $0) } ?? "N/A")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func bundleDetail(for bundle: TCFDRunArtifactBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selected Bundle")
                .font(.headline)
            Text("Run ID: \(bundle.runID)")
            Text("Output: \(bundle.outputDirectory)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Manifest: \(bundle.manifestURL)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let totalBurnt = bundle.totalBurnt, let totalCells = bundle.totalCells {
                Text("Burnt: \(totalBurnt) / \(totalCells)")
            }

            disclosureSection(title: "Governance", lines: bundle.governanceSummary)
            disclosureSection(title: "Strategy", lines: bundle.strategySummary)
            disclosureSection(title: "Risk Management", lines: bundle.riskManagementSummary)
            disclosureSection(title: "Metrics & Targets", lines: bundle.metricsSummary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
    }

    private func disclosureSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            if lines.isEmpty {
                Text("No summary available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { entry in
                    Text("• \(entry.element)")
                        .font(.footnote)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
    }
}

private struct GovernanceMetadataEditor: View {
    @Binding var metadata: GovernanceMetadata
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Board owner", text: $metadata.boardOwner)
            TextField("Management owner", text: $metadata.managementOwner)
            TextField("Approval status", text: $metadata.approvalStatus)
            DatePicker("Review date", selection: reviewDateBinding, displayedComponents: .date)
            TextField("Risk appetite notes", text: $metadata.riskAppetiteNotes, axis: .vertical)
                .lineLimit(3...6)
            TextField("Delegated authority notes", text: $metadata.delegatedAuthorityNotes, axis: .vertical)
                .lineLimit(3...6)

            Button("Save Governance") {
                onSave()
            }
        }
    }

    private var reviewDateBinding: Binding<Date> {
        Binding(
            get: { metadata.reviewDate ?? Date() },
            set: { metadata.reviewDate = $0 }
        )
    }
}
