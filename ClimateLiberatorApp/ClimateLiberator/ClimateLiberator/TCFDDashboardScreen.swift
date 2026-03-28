import SwiftUI
import AppKit

private enum TCFDSection: String, CaseIterable, Identifiable {
    case overview
    case scenarios
    case governance
    case strategy
    case targets
    case packages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .scenarios: return "Scenarios"
        case .governance: return "Governance"
        case .strategy: return "Strategy"
        case .targets: return "Targets"
        case .packages: return "Disclosure Packages"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .scenarios: return "bookmark"
        case .governance: return "building.columns"
        case .strategy: return "map"
        case .targets: return "scope"
        case .packages: return "doc.text.magnifyingglass"
        }
    }
}

struct TCFDDashboardScreen: View {
    @ObservedObject var scenarioStore: ScenarioLibraryStore
    @ObservedObject var reviewStore: TCFDReviewStore
    @ObservedObject var forecastStore: ForecastIntelligenceStore
    @State private var selection: TCFDSection? = .overview
    @State private var governanceDraft: GovernanceMetadata
    @State private var showingScenarioEditor = false
    @State private var editingScenario: ScenarioDefinition?
    @State private var statusMessage: String?
    @State private var reviewDraft: TCFDReviewRecord?
    @State private var selectedPackageDetailsExpanded = false
    @State private var hoveredSidebarSection: TCFDSection?
    @State private var hoveredScenarioID: UUID?
    @State private var hoveredBundleID: String?

    init(scenarioStore: ScenarioLibraryStore,
         reviewStore: TCFDReviewStore,
         forecastStore: ForecastIntelligenceStore) {
        self.scenarioStore = scenarioStore
        self.reviewStore = reviewStore
        self.forecastStore = forecastStore
        _governanceDraft = State(initialValue: scenarioStore.governanceMetadata)
        _reviewDraft = State(initialValue: reviewStore.selectedBundle?.reviewRecord)
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Text("TCFD Dashboard")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                ForEach(TCFDSection.allCases) { section in
                    tcfdSidebarButton(for: section)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(minWidth: 220, maxWidth: 240, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .underPageBackgroundColor))
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ZStack(alignment: .topLeading) {
                        content
                            .id(selection)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(24)
                .animation(.spring(response: 0.28, dampingFraction: 0.92), value: selection)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1120, minHeight: 760)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Packages") {
                    reviewStore.refreshFromDisk()
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
        .onChange(of: reviewStore.selectedBundleID) { _, _ in
            ensureSelectedReviewSnapshot()
        }
        .onAppear {
            ensureSelectedReviewSnapshot()
        }
    }

    private func tcfdSidebarButton(for section: TCFDSection) -> some View {
        let isHovered = hoveredSidebarSection == section
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                selection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 20)
                Text(section.title)
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected(section) ? Color.accentColor.opacity(0.16) : isHovered ? Color.secondary.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected(section) ? Color.accentColor.opacity(0.42) : isHovered ? Color.secondary.opacity(0.20) : Color.secondary.opacity(0.08), lineWidth: 1)
            )
            .offset(x: isHovered ? 1 : 0)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredSidebarSection = hovering ? section : (hoveredSidebarSection == section ? nil : hoveredSidebarSection)
            }
        }
    }

    private func isSelected(_ section: TCFDSection) -> Bool {
        selection == section
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Board Disclosure Workspace")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("TCFD Wildfire Dashboard")
                .font(.largeTitle.bold())
            Text("A dedicated disclosure workspace for governance, scenarios, target bands, and packaged wildfire evidence. This screen is intentionally separate from simulation controls and map tools.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                dashboardChip(label: "Scenario", value: selectedScenarioDescriptor, tone: .good)
                dashboardChip(label: "Latest Package", value: reviewStore.bundles.first?.runID ?? "No package yet", tone: reviewStore.bundles.isEmpty ? .neutral : .good)
                dashboardChip(label: "Board Readiness", value: latestReview?.packageState.displayName ?? "Awaiting review", tone: tone(for: latestReview?.packageState))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection ?? .overview {
        case .overview:
            overviewSection
        case .scenarios:
            scenariosSection
        case .governance:
            governanceSection
        case .strategy:
            strategySection
        case .targets:
            targetsSection
        case .packages:
            packagesSection
        }
    }

    private var overviewSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(minimum: 420), spacing: 16), GridItem(.flexible(minimum: 320), spacing: 16)], spacing: 16) {
            dashboardCard(title: "Disclosure Readiness", subtitle: "Board-facing status across governance, scenario framing, thresholds, and finance review.") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    readinessInsightCard(title: "Governance chain",
                                         value: governanceChainStatus.title,
                                         detail: governanceChainStatus.detail,
                                         tone: governanceChainStatus.tone)
                    readinessInsightCard(title: "Scenario framing",
                                         value: scenarioFramingStatus.title,
                                         detail: scenarioFramingStatus.detail,
                                         tone: scenarioFramingStatus.tone)
                    readinessInsightCard(title: "Threshold discipline",
                                         value: thresholdStatus.title,
                                         detail: thresholdStatus.detail,
                                         tone: thresholdStatus.tone)
                    readinessInsightCard(title: "Financial effects",
                                         value: financialStatus.title,
                                         detail: financialStatus.detail,
                                         tone: financialStatus.tone)
                }

                if let message = statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(reviewStore.discoveryStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                dashboardCard(title: "Action Center", subtitle: "Move directly into the review task you need.") {
                    HStack(spacing: 12) {
                        Button("New Scenario") {
                            editingScenario = nil
                            showingScenarioEditor = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh Packages") {
                            reviewStore.refreshFromDisk()
                            statusMessage = "Disclosure packages refreshed from disk."
                        }
                    }

                    Button("Open Latest Report") {
                        if let latest = reviewStore.bundles.first,
                           AppActionSupport.openExistingPath(latest.reportURL, expectation: .file) {
                            statusMessage = "Opened the latest disclosure report."
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!latestReportAvailability.isEnabled)

                    if let message = latestReportAvailability.reason ?? statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                dashboardCard(title: "Disclosure Pathways", subtitle: "Scenario pathway and horizon now frame the board narrative.") {
                    if scenarioStore.scenarios.isEmpty {
                        emptyState("No saved scenarios available yet.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                            ForEach(scenarioStore.scenarios.prefix(3)) { scenario in
                                scenarioMiniCard(for: scenario)
                            }
                        }
                    }
                }

                dashboardCard(title: "Forecast Support Evidence", subtitle: "Only disclosure-promoted forecast snapshots can support package interpretation.") {
                    if let snapshot = forecastStore.latestDisclosureSnapshot {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(snapshot.locationLabel)
                                .font(.headline)
                            Text("\(snapshot.horizon.capitalized) • \(snapshot.confidence.rawValue.capitalized) confidence")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(snapshot.statusSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        emptyState("No forecast snapshot has been promoted for disclosure support yet.")
                    }
                }
            }
        }
    }

    private var scenariosSection: some View {
        dashboardCard(title: "Scenario Library", subtitle: "Define disclosure-ready scenarios with pathway and horizon context.") {
            HStack {
                Spacer()
                Button("Add Scenario") {
                    editingScenario = nil
                    showingScenarioEditor = true
                }
                .buttonStyle(.borderedProminent)
            }

            if scenarioStore.scenarios.isEmpty {
                emptyState("No scenarios saved yet.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(scenarioStore.scenarios) { scenario in
                        scenarioDetailCard(for: scenario)
                    }
                }
            }
        }
    }

    private var governanceSection: some View {
        dashboardCard(title: "Governance Accountability", subtitle: "Show who owns climate oversight, review cadence, and ERM linkage.") {
            accountabilityStrip

            if let governance = latestReview?.governance ?? fallbackGovernanceSnapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    accountabilityMetricCard(title: "Board Committee",
                                             value: governance.boardCommittee ?? "Unassigned",
                                             detail: governance.boardOversightRequired == true ? "Board oversight required" : "Board oversight not marked required",
                                             tone: governance.boardOversightRequired == true ? .good : .warn)
                    accountabilityMetricCard(title: "Review Cadence",
                                             value: governance.reviewCadence ?? "Not specified",
                                             detail: governance.delegatedAuthoritySummary ?? "Delegated authority summary pending",
                                             tone: governance.reviewCadence == nil ? .warn : .good)
                    accountabilityMetricCard(title: "ERM Linkage",
                                             value: governance.ermLinkageSummary ?? "Unlinked",
                                             detail: governance.riskOwner?.name ?? "Risk owner not assigned",
                                             tone: governance.ermLinkageSummary == nil ? .warn : .good)
                }
            }

            TCFDDashboardGovernanceEditor(metadata: $governanceDraft) {
                scenarioStore.updateGovernanceMetadata(governanceDraft)
                statusMessage = "Governance metadata saved."
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var strategySection: some View {
        dashboardCard(title: "Strategy & Impact Drivers", subtitle: "Translate pathway choices into clear short-, medium-, and long-term consequences.") {
            if let review = latestReview {
                self.packageScenarioSection(review)
                Divider()
                self.packageImpactDriverSection(review)
            } else if let selected = scenarioStore.selectedScenario {
                scenarioPathwayCard(for: selected)
            } else {
                emptyState("Select an active scenario to frame the strategy view.")
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            dashboardCard(title: "Roadmap & Targets", subtitle: "Translate wildfire metrics into staged governance and disclosure milestones.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    roadmapCard(title: "Stage 1", subtitle: "Package generated", detail: "Manifest, report, and mapping bundle created from a successful run.", isComplete: reviewStore.bundles.isEmpty == false)
                    roadmapCard(title: "Stage 2", subtitle: "Thresholds reviewed", detail: thresholdRoadmapDetail, isComplete: latestReview?.thresholds.status != .notEvaluated)
                    roadmapCard(title: "Stage 3", subtitle: "Finance reviewed", detail: financeRoadmapDetail, isComplete: latestReview?.financialEffects.financeReviewed == true)
                    roadmapCard(title: "Stage 4", subtitle: "Board ready", detail: boardRoadmapDetail, isComplete: latestReview?.packageState == .readyForBoard)
                }
            }

            dashboardCard(title: "Target Bands", subtitle: "Maintain the wildfire metrics and tolerance bands that later reviews should test.") {
                HStack {
                    Spacer()
                    Button("Add Target Band") {
                        scenarioStore.upsertTargetBand(
                            TargetBand(metricName: "Burn probability", thresholdValue: 5.0, unit: "%", comparison: .lessThanOrEqual, notes: "Example target band")
                        )
                        statusMessage = "Added a new target band. Update its values before final review."
                    }
                    .buttonStyle(.borderedProminent)
                }

                if scenarioStore.targetBands.isEmpty {
                    emptyState("No target bands configured yet.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(scenarioStore.targetBands) { band in
                            targetBandCard(for: band)
                        }
                    }
                }
            }
        }
    }

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            dashboardCard(title: "Package Review", subtitle: "Open, inspect, and sign off on board-ready wildfire evidence bundles.") {
                Text(reviewStore.discoveryStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if reviewStore.bundles.isEmpty {
                    emptyState("No packages found. Complete a run in the main Climate Liberator workspace first.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(reviewStore.bundles) { bundle in
                            packageListCard(for: bundle)
                        }
                    }
                }
            }

            if let selected = reviewStore.selectedBundle {
                dashboardCard(title: "Selected Package", subtitle: "Review package details and open the generated files.") {
                    VStack(alignment: .leading, spacing: 14) {
                        if let record = reviewDraft ?? selected.reviewRecord {
                            packageDecisionCockpit(selected, record: record)
                        }

                        if let message = selectedPackageActionMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        DisclosureGroup(isExpanded: $selectedPackageDetailsExpanded) {
                            packageReviewDetailsPanel(selected)
                                .padding(.top, 10)
                        } label: {
                            HStack(spacing: 10) {
                                Text("Review details")
                                    .font(.subheadline.weight(.semibold))
                                Text(selectedPackageDetailsExpanded ? "Hide" : "Show")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func disclosureSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if lines.isEmpty {
                Text("No summary available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { line in
                    Text("• \(line.element)")
                        .font(.footnote)
                }
            }
        }
    }

    private func scenarioDetailCard(for scenario: ScenarioDefinition) -> some View {
        let isActive = scenarioStore.selectedScenarioID == scenario.id
        let header = scenarioDetailHeader(for: scenario, isActive: isActive)
        let pathwayRow = scenarioDetailPathwayRow(for: scenario)
        let noteView = scenario.notes.isEmpty ? AnyView(EmptyView()) : AnyView(
            Text(scenario.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
        )
        let runRow = scenarioDetailRunRow(for: scenario)
        let actions = scenarioDetailActions(for: scenario, isActive: isActive)

        return VStack(alignment: .leading, spacing: 12) {
            header
            pathwayRow
            noteView
            runRow
            Divider()
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(isActive ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.66)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private func scenarioDetailHeader(for scenario: ScenarioDefinition, isActive: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(scenario.name)
                    .font(.headline)
                Text(scenario.tcfdScenarioLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(isActive ? "Active" : "Saved")
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 999).fill(isActive ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12)))
        }
    }

    private func scenarioDetailPathwayRow(for scenario: ScenarioDefinition) -> some View {
        HStack(spacing: 8) {
            dashboardChip(label: "Pathway", value: scenario.pathwayLabel ?? "Pathway not set", tone: .neutral)
            dashboardChip(label: "Horizon", value: scenario.horizonLabel ?? "Horizon not set", tone: .neutral)
        }
    }

    private func scenarioDetailRunRow(for scenario: ScenarioDefinition) -> some View {
        HStack(spacing: 8) {
            dashboardChip(label: "Simulator", value: scenario.simulatorCode, tone: .good)
            dashboardChip(label: "Runs", value: "\(scenario.numberOfSimulations)x", tone: .neutral)
            dashboardChip(label: "Seed", value: "\(scenario.seed)", tone: .neutral)
        }
    }

    private func scenarioDetailActions(for scenario: ScenarioDefinition, isActive: Bool) -> some View {
        HStack {
            Button("Edit") {
                editingScenario = scenario
                showingScenarioEditor = true
            }
            Button(isActive ? "Active" : "Set Active") {
                scenarioStore.selectScenario(id: scenario.id)
                statusMessage = "\(scenario.name) is now the active disclosure scenario."
            }
            .disabled(isActive)
        }
    }

    private func scenarioPathwayCard(for scenario: ScenarioDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scenario Pathway")
                        .font(.headline)
                    Text(scenario.name)
                        .font(.title3.bold())
                }
                Spacer()
                Text(scenario.tcfdScenarioLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 999).fill(Color.accentColor.opacity(0.14)))
            }

            HStack(spacing: 10) {
                dashboardChip(label: "Pathway", value: scenario.pathwayLabel ?? "Unspecified pathway", tone: .good)
                dashboardChip(label: "Horizon", value: scenario.horizonLabel ?? "Unspecified horizon", tone: .warn)
            }

            Text(scenario.notes.isEmpty ? "Add a note to describe what this scenario means for board and management review." : scenario.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                dashboardChip(label: "Simulator", value: scenario.simulatorCode, tone: .good)
                dashboardChip(label: "Runs", value: "\(scenario.numberOfSimulations)x", tone: .neutral)
                dashboardChip(label: "Output", value: scenario.outputFormat.uppercased(), tone: .neutral)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(0.66)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func scenarioMiniCard(for scenario: ScenarioDefinition) -> some View {
        let isHovered = hoveredScenarioID == scenario.id
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.name)
                        .font(.headline)
                    Text(scenario.tcfdScenarioLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(scenarioStore.selectedScenarioID == scenario.id ? "Active" : "Saved")
                    .font(.caption2.weight(.bold))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 999).fill(Color.secondary.opacity(0.10)))
            }

            HStack(spacing: 8) {
                dashboardChip(label: "Pathway", value: scenario.pathwayLabel ?? "Unspecified", tone: .good)
                dashboardChip(label: "Horizon", value: scenario.horizonLabel ?? "Unspecified", tone: .warn)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.64)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scenarioStore.selectedScenarioID == scenario.id ? Color.accentColor.opacity(0.35) : isHovered ? Color.secondary.opacity(0.20) : Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: isHovered ? Color.black.opacity(0.04) : Color.clear, radius: 8, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredScenarioID = hovering ? scenario.id : (hoveredScenarioID == scenario.id ? nil : hoveredScenarioID)
            }
        }
        )
    }

    private func targetBandCard(for band: TargetBand) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(band.metricName)
                    .font(.headline)
                Text("\(band.comparison.displayName) \(band.thresholdValue, specifier: "%.2f") \(band.unit)")
                    .foregroundStyle(.secondary)
                if !band.notes.isEmpty {
                    Text(band.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Delete", role: .destructive) {
                scenarioStore.deleteTargetBand(id: band.id)
                statusMessage = "Target band deleted."
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.64)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func packageListCard(for bundle: TCFDRunArtifactBundle) -> some View {
        let header = packageListHeader(for: bundle)
        let meta = packageListMeta(for: bundle)
        let statusRow = packageListStatusRow(for: bundle)
        let dueDateView: AnyView = {
            if let dueDate = bundle.reviewRecord?.dueDate {
                return AnyView(
                    Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
            }
            return AnyView(EmptyView())
        }()
        let actions = packageListActions(for: bundle)

        return VStack(alignment: .leading, spacing: 10) {
            header
            meta
            statusRow
            dueDateView
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(reviewStore.selectedBundleID == bundle.id ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.66)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(reviewStore.selectedBundleID == bundle.id ? Color.accentColor.opacity(0.30) : Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            reviewStore.selectBundle(id: bundle.id)
        }
    }

    private func packageListHeader(for bundle: TCFDRunArtifactBundle) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bundle.runID)
                    .font(.headline)
                Text(bundle.simulatorLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(bundle.totalBurntPercent.map { String(format: "%.1f%% burnt", $0) } ?? "Burn % unavailable")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func packageListMeta(for bundle: TCFDRunArtifactBundle) -> some View {
        Text(bundle.timestamp.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func packageListStatusRow(for bundle: TCFDRunArtifactBundle) -> some View {
        HStack(spacing: 8) {
            dashboardChip(label: "Governance", value: bundle.reviewRecord?.reviewStatus.displayName ?? "Packaged", tone: tone(for: bundle.reviewRecord?.reviewStatus))
            dashboardChip(label: "Package", value: bundle.reviewRecord?.packageState.displayName ?? "Generated", tone: tone(for: bundle.reviewRecord?.packageState))
            dashboardChip(label: "Escalation", value: bundle.reviewRecord?.escalationSeverity.displayName ?? "None", tone: tone(for: bundle.reviewRecord?.escalationSeverity))
        }
    }

    private func packageListActions(for bundle: TCFDRunArtifactBundle) -> some View {
        HStack {
            Button("Open Report") {
                _ = AppActionSupport.openExistingPath(bundle.reportURL, expectation: .file)
            }
            .buttonStyle(.borderedProminent)
            Button("Reveal Folder") {
                _ = AppActionSupport.openExistingPath(bundle.bundleURL, expectation: .directory)
            }
            .buttonStyle(.bordered)
        }
    }

    private func packageActionButton(title: String, availability: ActionAvailability, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .disabled(!availability.isEnabled)
            .buttonStyle(.bordered)
            .help(availability.reason ?? title)
    }

    private func dashboardChip(label: String, value: String, tone: DashboardTone) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(tone.fill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tone.color.opacity(0.16), lineWidth: 1))
    }

    private func metricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(0.66)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private var fallbackGovernanceSnapshot: GovernanceAccountabilitySnapshot? {
        let board = governanceDraft.boardOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let management = governanceDraft.managementOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let riskOwner = latestReview?.accountableExecutive ?? latestReview?.currentOwner
        guard !board.isEmpty ||
                !management.isEmpty ||
                riskOwner != nil ||
                !governanceDraft.approvalStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return GovernanceAccountabilitySnapshot(
            boardCommittee: board.isEmpty ? nil : board,
            boardOversightRequired: true,
            managementOwner: management.isEmpty ? nil : PersonRef(name: management, title: "Management Owner"),
            riskOwner: riskOwner,
            financeReviewer: latestReview?.financialEffects.financeReviewed == true ? PersonRef(name: "Finance Review", title: "Completed") : nil,
            reviewCadence: "Saved governance metadata",
            delegatedAuthoritySummary: governanceDraft.delegatedAuthorityNotes.isEmpty ? nil : governanceDraft.delegatedAuthorityNotes,
            ermLinkageSummary: governanceDraft.riskAppetiteNotes.isEmpty ? nil : governanceDraft.riskAppetiteNotes
        )
    }

    private func dashboardCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(nsColor: .controlBackgroundColor).opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 4)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.50)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func readinessInsightCard(title: String, value: String, detail: String, tone: DashboardTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Circle()
                    .fill(tone.color)
                    .frame(width: 10, height: 10)
            }
            Text(value)
                .font(.title3.bold())
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(tone.fill))
    }

    private func horizonCard(title: String, timeframe: String, focus: String, scenario: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(timeframe)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(focus)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            Text(scenario)
                .font(.footnote.weight(.medium))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(0.64)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func impactDriverCard(_ driver: WildfireImpactDriver) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(driver.category.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(driver.tone.color)
                Spacer()
                Circle()
                    .fill(driver.tone.color)
                    .frame(width: 9, height: 9)
            }
            Text(driver.title)
                .font(.headline)
            Text(driver.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(0.64)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func accountabilityCard(title: String, name: String?, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayNameOrPlaceholder(name))
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.64)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func accountabilityMetricCard(title: String, value: String, detail: String, tone: DashboardTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Circle()
                    .fill(tone.color)
                    .frame(width: 10, height: 10)
            }
            Text(value)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(tone.fill))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tone.color.opacity(0.18), lineWidth: 1))
    }

    private func impactDriverMatrixCard(_ driver: WildfireImpactDriverAssessment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(driver.driverName)
                    .font(.headline)
                Spacer()
                dashboardChip(label: driver.category.displayName, value: driver.ermLinked ? "ERM linked" : "Standalone", tone: driver.ermLinked ? .good : .warn)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                packageMilestoneCard(title: "Short", value: "0-3 years", subtitle: driver.shortTermView, tone: .neutral)
                packageMilestoneCard(title: "Medium", value: "3-10 years", subtitle: driver.mediumTermView, tone: .neutral)
                packageMilestoneCard(title: "Long", value: "10+ years", subtitle: driver.longTermView, tone: .neutral)
            }

            if !driver.responseSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(driver.responseSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.60)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func reviewStatusChip(title: String, value: String, tone: DashboardTone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(tone.fill))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tone.color.opacity(0.16), lineWidth: 1))
    }

    private func packageMilestoneCard(title: String, value: String, subtitle: String, tone: DashboardTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(tone.color)
                    .frame(width: 9, height: 9)
            }
            Text(value)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.60)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func roadmapCard(title: String, subtitle: String, detail: String, isComplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isComplete ? "checkmark.seal.fill" : "clock")
                    .foregroundStyle(isComplete ? Color.green : Color.orange)
            }
            Text(subtitle)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(0.64)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func displayNameOrPlaceholder(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Unassigned"
        }
        return value
    }

    private func stringIsPresent(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accountabilityStrip: some View {
        let record = reviewDraft ?? reviewStore.selectedBundle?.reviewRecord
        let governance = record?.governance ?? fallbackGovernanceSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            Text("Accountability Chain")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                accountabilityCard(title: "Board Owner",
                                   name: governanceDraft.boardOwner,
                                   subtitle: governance?.boardCommittee ?? "Governance owner")
                accountabilityCard(title: "Management Owner",
                                   name: governance?.managementOwner?.name ?? governanceDraft.managementOwner,
                                   subtitle: governance?.managementOwner?.title ?? "Operational sponsor")
                accountabilityCard(title: "Current Review Owner",
                                   name: record?.currentOwner?.name,
                                   subtitle: record?.currentOwner?.title ?? "Not assigned")
                accountabilityCard(title: "Executive Owner",
                                   name: record?.accountableExecutive?.name,
                                   subtitle: record?.accountableExecutive?.title ?? "Not assigned")
                accountabilityCard(title: "Risk Owner",
                                   name: governance?.riskOwner?.name,
                                   subtitle: governance?.riskOwner?.title ?? "Not assigned")
                accountabilityCard(title: "Finance Reviewer",
                                   name: governance?.financeReviewer?.name,
                                   subtitle: governance?.financeReviewer?.title ?? "Not assigned")
                accountabilityCard(title: "Approver",
                                   name: record?.approver?.name,
                                   subtitle: record?.approver?.title ?? "Not assigned")
            }
        }
    }

    private func packageReviewSummary(_ bundle: TCFDRunArtifactBundle) -> some View {
        let record = reviewDraft ?? bundle.reviewRecord
        return VStack(alignment: .leading, spacing: 12) {
            Text("Review Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                reviewStatusChip(title: "Review", value: record?.reviewStatus.displayName ?? "Not started", tone: tone(for: record?.reviewStatus))
                reviewStatusChip(title: "Package", value: record?.packageState.displayName ?? "Generated", tone: tone(for: record?.packageState))
                reviewStatusChip(title: "Decision", value: record?.decision.displayName ?? "None", tone: tone(for: record?.decision))
                reviewStatusChip(title: "Escalation", value: record?.escalationSeverity.displayName ?? "None", tone: tone(for: record?.escalationSeverity))
            }

            if let record {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    packageMilestoneCard(title: "Thresholds", value: record.thresholds.status.displayName, subtitle: "\(record.thresholds.breachedCount) breached / \(record.thresholds.nearLimitCount) near limit", tone: tone(for: record.thresholds.status))
                    packageMilestoneCard(title: "Finance", value: record.financialEffects.status.displayName, subtitle: financeSubtitle(for: record), tone: tone(for: record.financialEffects.status))
                    packageMilestoneCard(title: "Provenance", value: record.provenance.isComplete ? "Complete" : "Incomplete", subtitle: record.provenance.simulatorLabel, tone: record.provenance.isComplete ? .good : .warn)
                    packageMilestoneCard(title: "Due", value: dueDateLabel(for: record), subtitle: record.reviewStatus.displayName, tone: record.escalationSeverity == .critical ? .critical : .neutral)
                }

                HStack(spacing: 10) {
                    dashboardChip(label: "Scenario", value: record.scenario.tcfdScenarioLabel, tone: .good)
                    dashboardChip(label: "Horizon", value: record.scenario.shortHorizonLabel ?? record.scenario.mediumHorizonLabel ?? record.scenario.longHorizonLabel ?? "Not set", tone: .neutral)
                    dashboardChip(label: "Driver Count", value: "\(record.impactDrivers?.count ?? 0)", tone: .neutral)
                    dashboardChip(label: "Board Committee", value: record.governance?.boardCommittee ?? "Unassigned", tone: .warn)
                }

                DisclosureGroup("Board readiness checklist") {
                    boardReadinessChecklist(record)
                }
            }
        }
    }

    private func packageDecisionCockpit(_ bundle: TCFDRunArtifactBundle, record: TCFDReviewRecord) -> some View {
        let reviewIssues = reviewStore.readyForReviewIssues(for: record)
        let boardIssues = reviewStore.readyForBoardIssues(for: record)
        let comparisonIssues = reviewStore.comparisonIssues(for: record)
        let approvalIssues = reviewStore.approvalIssues(for: record)
        let historyIssues = reviewStore.historyIntegrityIssues(for: record)
        let executiveReady = reviewIssues.isEmpty && record.thresholds.status != .notEvaluated
        let nextDecision = nextDecisionPrompt(for: record, reviewIssues: reviewIssues, boardIssues: boardIssues)
        let blockerSource = record.reviewStatus == .boardPackReady
            ? boardIssues + approvalIssues + historyIssues
            : (reviewIssues.isEmpty ? boardIssues + comparisonIssues + historyIssues : reviewIssues + historyIssues)
        let blockers = Array(uniqueIssues(blockerSource).prefix(4))
        let approvalStateLabel: String
        let approvalStateTone: DashboardTone
        if record.reviewStatus == .approved || record.reviewStatus == .approvedWithConditions {
            approvalStateLabel = record.reviewStatus.displayName
            approvalStateTone = tone(for: record.reviewStatus)
        } else if record.reviewStatus == .boardPackReady {
            approvalStateLabel = "Board Pack Ready"
            approvalStateTone = .good
        } else {
            approvalStateLabel = "Board Pack Pending"
            approvalStateTone = .warn
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bundle.runID)
                        .font(.title3.bold())
                    Text("Board-pack decision cockpit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(selectedScenarioDescriptor)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(approvalStateLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 999).fill(approvalStateTone.color.opacity(0.14)))
                    if let approvedAt = record.approvedAt {
                        Text("Approved \(approvedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                dashboardChip(label: "Scenario", value: record.scenario.tcfdScenarioLabel, tone: .good)
                dashboardChip(label: "Pathway", value: record.scenario.baselineScenarioName ?? "Not set", tone: .neutral)
                dashboardChip(label: "Comparator", value: record.scenario.comparatorScenarioName ?? "Not set", tone: .neutral)
                dashboardChip(label: "Horizon", value: record.scenario.shortHorizonLabel ?? record.scenario.mediumHorizonLabel ?? record.scenario.longHorizonLabel ?? "Not set", tone: .neutral)
                dashboardChip(label: "Simulator", value: record.scenario.simulatorLabel, tone: .neutral)
            }

            packageComparisonEvidence(for: record)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("Export Board Pack") {
                        exportSelectedBoardPack(openAfterExport: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!exportBoardPackAvailability.isEnabled)
                    .help(exportBoardPackAvailability.reason ?? "Export the approved board pack.")

                    Button("Open Board Pack") {
                        if let url = reviewStore.boardPackReportURL(for: bundle.runID),
                           AppActionSupport.openExistingPath(url.path, expectation: .file) {
                            statusMessage = "Opened the approved board pack for \(bundle.runID)."
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!selectedBoardPackAvailability.isEnabled)
                    .help(selectedBoardPackAvailability.reason ?? "Open the approved board pack.")

                    Spacer(minLength: 0)

                    Button("Sync Snapshot") {
                        syncSelectedReviewSnapshot()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("Open Run Report") {
                        if AppActionSupport.openExistingPath(bundle.reportURL, expectation: .file) {
                            statusMessage = "Opened \(bundle.runID)."
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!selectedReportAvailability.isEnabled)
                    .help(selectedReportAvailability.reason ?? "Open the disclosure report.")

                    Button("Reveal Folder") {
                        if AppActionSupport.openExistingPath(bundle.bundleURL, expectation: .directory) {
                            statusMessage = "Opened the package folder for \(bundle.runID)."
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!selectedFolderAvailability.isEnabled)
                    .help(selectedFolderAvailability.reason ?? "Reveal the package folder.")

                    Spacer(minLength: 0)
                }
            }

            if let message = selectedPackageActionMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: exportBoardPackAvailability.isEnabled ? "checkmark.seal.fill" : "info.circle.fill")
                        .foregroundStyle(exportBoardPackAvailability.isEnabled ? Color.green : Color.secondary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor).opacity(0.56)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                packageMilestoneCard(title: "Required Decision",
                                     value: record.decision == .none ? "Decision Needed" : record.decision.displayName,
                                     subtitle: nextDecision,
                                     tone: record.decision == .none ? .warn : tone(for: record.decision))
                packageMilestoneCard(title: "Executive Ready",
                                     value: executiveReady ? "Yes" : "No",
                                     subtitle: executiveReady ? "Suitable for leadership monitoring." : "Resolve review-gate issues before executive review.",
                                     tone: executiveReady ? .good : .warn)
                packageMilestoneCard(title: "Board Ready",
                                     value: boardIssues.isEmpty && record.reviewStatus == .boardPackReady ? "Confirmed" : "Blocked",
                                     subtitle: boardIssues.isEmpty ? "Explicit board-pack action recorded." : "\(boardIssues.count) blocking issue(s) remain.",
                                     tone: boardIssues.isEmpty && record.reviewStatus == .boardPackReady ? .good : .critical)
                packageMilestoneCard(title: "Workflow Integrity",
                                     value: historyIssues.isEmpty ? "Clean" : "Attention",
                                     subtitle: historyIssues.isEmpty ? "Timeline evidence is internally consistent." : "\(historyIssues.count) audit issue(s) need cleanup.",
                                     tone: historyIssues.isEmpty ? .good : .warn)
                packageMilestoneCard(title: "Review Events",
                                     value: "\((record.reviewEvents ?? []).count)",
                                     subtitle: (record.reviewEvents ?? []).last.map { "\($0.action) • \($0.timestamp.formatted(date: .abbreviated, time: .shortened))" } ?? "No workflow events recorded yet.",
                                     tone: (record.reviewEvents ?? []).isEmpty ? .warn : .neutral)
            }

            packageBlockingSummary(blockers: blockers)
        }
    }

    private func packageReviewDetailsPanel(_ bundle: TCFDRunArtifactBundle) -> some View {
        let record = reviewDraft ?? bundle.reviewRecord

        return VStack(alignment: .leading, spacing: 14) {
            Text("Review details")
                .font(.headline)

            Text("The approved board-pack export is a frozen snapshot from the current review record. Edit the review record only when you intend to refresh governance, thresholds, or scenario context.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if reviewDraft != nil {
                TCFDReviewRecordEditor(reviewStore: reviewStore, record: reviewDraftBinding) {
                    if let reviewDraft {
                        reviewStore.upsertReviewRecord(reviewDraft)
                        statusMessage = "Review workflow saved for \(bundle.runID)."
                    }
                }
            }

            if let record {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    packageDetailCard(title: "Governance & Approval", subtitle: "Owners, decision state, and review chain.") {
                        packageReviewSummary(bundle)
                        packageGovernanceSection(record)
                        disclosureSection(title: "Governance", lines: bundle.governanceSummary)
                        disclosureSection(title: "Risk Management", lines: bundle.riskManagementSummary)
                    }

                    packageDetailCard(title: "Scenario & Strategy", subtitle: "Pathway, horizon, and impact drivers.") {
                        packageScenarioSection(record)
                        packageImpactDriverSection(record)
                        disclosureSection(title: "Strategy", lines: bundle.strategySummary)
                    }

                    packageDetailCard(title: "Metrics, Provenance & Targets", subtitle: "Thresholds, finance, and evidence trail.") {
                        packageFinancialAndProvenanceSection(record)
                        disclosureSection(title: "Metrics & Targets", lines: bundle.metricsSummary)
                    }

                    packageDetailCard(title: "Review Event History", subtitle: "Append-only workflow and export events captured for auditability.") {
                        packageReviewEventSection(record)
                    }
                }
            }
        }
    }

    private func packageReviewEventSection(_ record: TCFDReviewRecord) -> some View {
        let events = (record.reviewEvents ?? []).sorted { $0.timestamp > $1.timestamp }

        return VStack(alignment: .leading, spacing: 10) {
            if let evidenceNote = record.approvalEvidence?.evidenceNote,
               !evidenceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(evidenceNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if events.isEmpty {
                Text("No workflow events are recorded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(6)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.action)
                                .font(.subheadline.weight(.semibold))
                            Text("\(event.reviewStatus.displayName) • \(event.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let note = event.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func packageDetailCard(title: String,
                                   subtitle: String,
                                   @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .controlBackgroundColor).opacity(0.56)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private func boardReadinessChecklist(_ record: TCFDReviewRecord) -> some View {
        let items = boardReadinessItems(for: record)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Board Readiness Checklist")
                .font(.headline)

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.isComplete ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor).opacity(0.58)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
            }
        }
    }

    private func packageGovernanceSection(_ record: TCFDReviewRecord) -> some View {
        let governance = record.governance ?? fallbackGovernanceSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            Text("Governance Accountability")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                accountabilityMetricCard(title: "Board Committee",
                                         value: governance?.boardCommittee ?? "Unassigned",
                                         detail: governance?.boardOversightRequired == true ? "Board oversight required" : "Board oversight not marked required",
                                         tone: governance?.boardOversightRequired == true ? .good : .warn)
                accountabilityMetricCard(title: "Executive Accountability",
                                         value: displayNameOrPlaceholder(record.accountableExecutive?.name),
                                         detail: record.accountableExecutive?.title ?? "Accountable executive not assigned",
                                         tone: record.accountableExecutive?.isEmpty == false ? .good : .warn)
                accountabilityMetricCard(title: "Risk / ERM Owner",
                                         value: displayNameOrPlaceholder(governance?.riskOwner?.name),
                                         detail: governance?.ermLinkageSummary ?? "ERM linkage summary pending",
                                         tone: governance?.riskOwner?.isEmpty == false ? .good : .warn)
                accountabilityMetricCard(title: "Delegated Authority",
                                         value: governance?.reviewCadence ?? "Review cadence pending",
                                         detail: governance?.delegatedAuthoritySummary ?? "Delegated authority summary pending",
                                         tone: governance?.reviewCadence == nil ? .warn : .good)
            }
        }
    }

    private func packageScenarioSection(_ record: TCFDReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenario Comparison")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                horizonCard(title: "Short Term",
                            timeframe: record.scenario.shortHorizonLabel ?? "0-3 years",
                            focus: record.scenario.shortTermDeltaSummary ?? "Operational wildfire exposure, readiness of controls, and acute disruption.",
                            scenario: record.scenario.baselineScenarioName ?? record.scenario.scenarioName)
                horizonCard(title: "Medium Term",
                            timeframe: record.scenario.mediumHorizonLabel ?? "3-10 years",
                            focus: record.scenario.mediumTermDeltaSummary ?? "Adaptation planning, insurance posture, and resilience investment sequencing.",
                            scenario: record.scenario.comparatorScenarioName ?? record.scenario.tcfdScenarioLabel)
                horizonCard(title: "Long Term",
                            timeframe: record.scenario.longHorizonLabel ?? "10+ years",
                            focus: record.scenario.longTermDeltaSummary ?? "Portfolio resilience under higher warming and chronic wildfire pressure.",
                            scenario: record.scenario.scenarioName)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                packageMilestoneCard(title: "Baseline Run",
                                     value: record.scenario.baselineRunID ?? "Missing",
                                     subtitle: record.scenario.baselineScenarioName ?? "Baseline scenario pending",
                                     tone: stringIsPresent(record.scenario.baselineRunID) ? .good : .warn)
                packageMilestoneCard(title: "Comparator Run",
                                     value: record.scenario.comparatorRunID ?? "Missing",
                                     subtitle: record.scenario.comparatorScenarioName ?? "Comparator scenario pending",
                                     tone: stringIsPresent(record.scenario.comparatorRunID) ? .good : .warn)
                packageMilestoneCard(title: "Resilience Conclusion",
                                     value: stringIsPresent(record.scenario.resilienceConclusion) ? "Defined" : "Missing",
                                     subtitle: record.scenario.resilienceConclusion ?? "Add a resilience conclusion based on scenario deltas.",
                                     tone: stringIsPresent(record.scenario.resilienceConclusion) ? .good : .warn)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Wildfire Assumptions")
                    .font(.subheadline.weight(.semibold))
                Text(record.scenario.wildfireAssumptionsSummary ?? "Assumption summary pending.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func packageImpactDriverSection(_ record: TCFDReviewRecord) -> some View {
        let drivers = record.impactDrivers ?? []
        return VStack(alignment: .leading, spacing: 12) {
            Text("Wildfire Impact Drivers")
                .font(.headline)

            if drivers.isEmpty {
                Text("No impact drivers captured yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ImpactDriverCategory.allCases) { category in
                    let categoryDrivers = drivers.filter { $0.category == category }
                    if !categoryDrivers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.displayName)
                                .font(.subheadline.bold())
                            ForEach(categoryDrivers) { driver in
                                impactDriverMatrixCard(driver)
                            }
                        }
                    }
                }
            }
        }
    }

    private func packageFinancialAndProvenanceSection(_ record: TCFDReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial Effects & Provenance")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                packageMilestoneCard(title: "Financial Effects", value: record.financialEffects.status.displayName, subtitle: record.financialEffects.magnitudeBand ?? "Magnitude band pending", tone: tone(for: record.financialEffects.status))
                packageMilestoneCard(title: "Finance Review", value: record.financialEffects.financeReviewed ? "Reviewed" : "Pending", subtitle: record.financialEffects.methodologyNote ?? "Methodology note pending", tone: record.financialEffects.financeReviewed ? .good : .warn)
                packageMilestoneCard(title: "Ground-Up Loss",
                                     value: formattedFinancialValue(record.financialEffects.estimatedGroundUpLoss, currencyCode: record.financialEffects.currencyCode),
                                     subtitle: record.financialEffects.exposureValue == nil ? "Set an exposure basis to estimate loss." : "Indicative proxy from exposure, burn, and vulnerability inputs.",
                                     tone: record.financialEffects.estimatedGroundUpLoss == nil ? .neutral : .warn)
                packageMilestoneCard(title: "Insured Loss",
                                     value: formattedFinancialValue(record.financialEffects.estimatedInsuredLoss, currencyCode: record.financialEffects.currencyCode),
                                     subtitle: record.financialEffects.limitPct == nil ? "Policy terms not yet provided." : "Deductible and limit applied to the indicative loss proxy.",
                                     tone: record.financialEffects.estimatedInsuredLoss == nil ? .neutral : .good)
                packageMilestoneCard(title: "Provenance", value: record.provenance.isComplete ? "Complete" : "Incomplete", subtitle: record.provenance.binaryHash ?? "Binary hash pending", tone: record.provenance.isComplete ? .good : .warn)
                packageMilestoneCard(title: "Artifacts", value: record.provenance.artifactIndexURL == nil ? "Index pending" : "Index available", subtitle: record.provenance.manifestURL, tone: record.provenance.artifactIndexURL == nil ? .warn : .good)
            }

            if !record.financialEffects.planningImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(record.financialEffects.planningImpactSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func financeSubtitle(for record: TCFDReviewRecord) -> String {
        let magnitude = record.financialEffects.magnitudeBand?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let magnitude, !magnitude.isEmpty {
            return record.financialEffects.financeReviewed ? "Reviewed • \(magnitude)" : "Pending • \(magnitude)"
        }
        return record.financialEffects.financeReviewed ? "Reviewed by finance" : "Finance review pending"
    }

    private func formattedFinancialValue(_ value: Double?, currencyCode: String?) -> String {
        guard let value else { return "Pending" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        if let currencyCode, !currencyCode.isEmpty {
            return "\(currencyCode) \(amount)"
        }
        return amount
    }

    private func dueDateLabel(for record: TCFDReviewRecord) -> String {
        guard let dueDate = record.dueDate else { return "No due date" }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var latestReportAvailability: ActionAvailability {
        guard let latest = reviewStore.bundles.first else {
            return .unavailable("Generate a wildfire run package before opening a report.")
        }
        return AppActionSupport.pathAvailability(
            path: latest.reportURL,
            expectation: .file,
            emptyReason: "The latest package does not include a report path.",
            missingReason: "The latest report file is missing from disk."
        )
    }

    private var selectedReportAvailability: ActionAvailability {
        guard let selected = reviewStore.selectedBundle else {
            return .unavailable("Select a disclosure package first.")
        }
        return AppActionSupport.pathAvailability(
            path: selected.reportURL,
            expectation: .file,
            emptyReason: "This package does not declare a report file.",
            missingReason: "The selected report file cannot be found on disk."
        )
    }

    private var selectedReviewRecordAvailability: ActionAvailability {
        guard let selected = reviewStore.selectedBundle else {
            return .unavailable("Select a disclosure package first.")
        }
        return AppActionSupport.pathAvailability(
            path: selected.reviewRecordURL,
            expectation: .file,
            emptyReason: "This package does not declare a review record.",
            missingReason: "The review record file cannot be found on disk."
        )
    }

    private var selectedFolderAvailability: ActionAvailability {
        guard let selected = reviewStore.selectedBundle else {
            return .unavailable("Select a disclosure package first.")
        }
        return AppActionSupport.pathAvailability(
            path: selected.bundleURL,
            expectation: .directory,
            emptyReason: "This package does not declare a bundle folder.",
            missingReason: "The selected package folder cannot be found on disk."
        )
    }

    private var selectedPackageActionMessage: String? {
        if !exportBoardPackAvailability.isEnabled {
            return exportBoardPackAvailability.reason
        }
        if !selectedBoardPackAvailability.isEnabled,
           let reason = selectedBoardPackAvailability.reason,
           reason != "Export the final board pack after approval." {
            return reason
        }
        if !selectedReportAvailability.isEnabled {
            return selectedReportAvailability.reason
        }
        if !selectedFolderAvailability.isEnabled {
            return selectedFolderAvailability.reason
        }
        if !selectedReviewRecordAvailability.isEnabled {
            return selectedReviewRecordAvailability.reason
        }
        return statusMessage
    }

    private var reviewDraftBinding: Binding<TCFDReviewRecord> {
        Binding(
            get: { reviewDraft ?? reviewStore.selectedBundle?.reviewRecord ?? TCFDReviewRecord.placeholder },
            set: { reviewDraft = $0 }
        )
    }

    private var latestReview: TCFDReviewRecord? {
        reviewDraft ?? reviewStore.selectedBundle?.reviewRecord ?? reviewStore.bundles.first?.reviewRecord
    }

    private var selectedScenarioDescriptor: String {
        if let selectedScenario = scenarioStore.selectedScenario {
            let pathway = selectedScenario.pathwayLabel ?? "Unspecified pathway"
            let horizon = selectedScenario.horizonLabel ?? "Unspecified horizon"
            return "\(selectedScenario.name) • \(pathway) • \(horizon)"
        }
        return "No active disclosure scenario"
    }

    private var governanceChainStatus: DashboardStatus {
        let review = latestReview
        if !governanceDraft.boardOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !governanceDraft.managementOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            review?.currentOwner?.isEmpty == false &&
            review?.approver?.isEmpty == false {
            return DashboardStatus(title: "Assigned", detail: "Board, management, review owner, and approver are all named.", tone: .good)
        }
        return DashboardStatus(title: "Incomplete", detail: "One or more governance owners are still missing.", tone: .warn)
    }

    private var scenarioFramingStatus: DashboardStatus {
        if let scenario = scenarioStore.selectedScenario,
           !scenario.tcfdScenarioLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pathway = scenario.pathwayLabel ?? "pathway pending"
            let horizon = scenario.horizonLabel ?? "horizon pending"
            return DashboardStatus(title: "Defined", detail: "\(scenario.name) frames \(pathway) across the \(horizon).", tone: .good)
        }
        return DashboardStatus(title: "Missing", detail: "Select a disclosure scenario before formal review.", tone: .warn)
    }

    private var thresholdStatus: DashboardStatus {
        guard let review = latestReview else {
            return DashboardStatus(title: "Waiting", detail: "No package review record is active yet.", tone: .neutral)
        }
        switch review.thresholds.status {
        case .withinTolerance:
            return DashboardStatus(title: "Within tolerance", detail: "Threshold review is complete with no breaches.", tone: .good)
        case .nearLimit:
            return DashboardStatus(title: "Near limit", detail: "\(review.thresholds.nearLimitCount) metrics are close to tolerance.", tone: .warn)
        case .breached:
            return DashboardStatus(title: "Breached", detail: "\(review.thresholds.breachedCount) metrics breached current target bands.", tone: .critical)
        case .notEvaluated:
            return DashboardStatus(title: "Not evaluated", detail: "Target bands exist but package-level assessment is still pending.", tone: .neutral)
        }
    }

    private var financialStatus: DashboardStatus {
        guard let review = latestReview else {
            return DashboardStatus(title: "Waiting", detail: "No financial-effects review has started yet.", tone: .neutral)
        }
        switch review.financialEffects.status {
        case .indicativeRange, .quantified:
            return DashboardStatus(title: "Captured", detail: review.financialEffects.financeReviewed ? "Finance review completed." : "Financial summary drafted.", tone: review.financialEffects.financeReviewed ? .good : .warn)
        case .qualitativeOnly:
            return DashboardStatus(title: "Qualitative", detail: "Financial impacts are described but not yet quantified.", tone: .warn)
        case .notStarted:
            return DashboardStatus(title: "Not started", detail: "Financial planning effects still need to be recorded.", tone: .critical)
        }
    }

    private var wildfireImpactDrivers: [WildfireImpactDriver] {
        let bundle = reviewStore.selectedBundle ?? reviewStore.bundles.first
        let burntPercent = bundle?.totalBurntPercent ?? 0
        let thresholdBreached = latestReview?.thresholds.status == .breached || (latestReview?.thresholds.breachedCount ?? 0) > 0
        let financeStarted = latestReview?.financialEffects.status != .notStarted

        return [
            WildfireImpactDriver(category: "Physical", title: "Acute wildfire events", detail: burntPercent > 15 ? "Recent runs show material burn outcomes that should be escalated." : "Current burn outcomes remain within a lower operational range.", tone: burntPercent > 15 ? .critical : .good),
            WildfireImpactDriver(category: "Physical", title: "Asset exposure", detail: bundle == nil ? "No package selected yet." : "Package metrics and nearby-site screening are available for asset-level review.", tone: bundle == nil ? .neutral : .good),
            WildfireImpactDriver(category: "Risk Management", title: "Threshold tolerance", detail: thresholdBreached ? "Target bands were breached and require a management response." : "No recorded breach in the active review record.", tone: thresholdBreached ? .critical : .good),
            WildfireImpactDriver(category: "Transition", title: "Insurance and financial pressure", detail: financeStarted ? "Financial effects are being captured in the review workflow." : "Financial effects have not yet been translated into planning terms.", tone: financeStarted ? .warn : .critical),
            WildfireImpactDriver(category: "Operations", title: "Operational disruption", detail: bundle?.riskManagementSummary.first ?? "Run packages should capture operational disruption implications.", tone: bundle == nil ? .neutral : .warn),
            WildfireImpactDriver(category: "Opportunity", title: "Resilience and adaptation", detail: bundle?.strategySummary.first ?? "Scenario-led adaptation opportunities should be documented per package.", tone: .good)
        ]
    }

    private var thresholdRoadmapDetail: String {
        guard let review = latestReview else { return "Select or generate a package to begin threshold review." }
        return review.thresholds.status.displayName
    }

    private var financeRoadmapDetail: String {
        guard let review = latestReview else { return "No financial review has started yet." }
        return review.financialEffects.status.displayName
    }

    private var boardRoadmapDetail: String {
        guard let review = latestReview else { return "No package is ready for board distribution yet." }
        return review.packageState.displayName
    }

    private func nextDecisionPrompt(for record: TCFDReviewRecord,
                                    reviewIssues: [String],
                                    boardIssues: [String]) -> String {
        if !reviewIssues.isEmpty {
            return reviewIssues.first ?? "Resolve review-gate issues."
        }
        switch record.reviewStatus {
        case .packaged:
            return "Submit this package into analyst review."
        case .analystReview:
            return "Advance the package to risk-owner review once analyst checks are complete."
        case .riskOwnerReview:
            return "Advance the package to management review with a named executive owner."
        case .managementReview:
            return boardIssues.isEmpty ? "Mark the package Board Pack Ready." : (boardIssues.first ?? "Resolve board-readiness blockers.")
        case .boardPackReady:
            return "Record an approval decision or request changes."
        case .approved, .approvedWithConditions:
            return "Package is closed. Supersede it only if a newer package replaces this evidence."
        case .changesRequested:
            return "Resolve requested changes, then resubmit for analyst or risk-owner review."
        case .rejected:
            return "Package is rejected. Generate or prepare a replacement package if review should continue."
        case .superseded:
            return "This package has been replaced by a newer review package."
        }
    }

    private func boardReadinessItems(for record: TCFDReviewRecord) -> [BoardReadinessItem] {
        let reviewIssues = reviewStore.readyForReviewIssues(for: record)
        let boardIssues = reviewStore.readyForBoardIssues(for: record)
        let governanceIssueCount = boardIssues.filter {
            $0.localizedCaseInsensitiveContains("owner") ||
            $0.localizedCaseInsensitiveContains("board") ||
            $0.localizedCaseInsensitiveContains("cadence") ||
            $0.localizedCaseInsensitiveContains("delegated") ||
            $0.localizedCaseInsensitiveContains("ERM")
        }.count
        let financeIssueCount = boardIssues.filter {
            $0.localizedCaseInsensitiveContains("financial") ||
            $0.localizedCaseInsensitiveContains("finance")
        }.count

        return [
            BoardReadinessItem(
                title: "Ready for review gate",
                detail: reviewIssues.isEmpty
                    ? "The package meets the minimum package, scenario, provenance, and due-date requirements for analyst review."
                    : reviewIssues.first ?? "Review-gate requirements are incomplete.",
                isComplete: reviewIssues.isEmpty
            ),
            BoardReadinessItem(
                title: "Governance chain assigned",
                detail: governanceIssueCount == 0
                    ? "Governance accountability, cadence, delegated authority, and ERM linkage are complete."
                    : "\(governanceIssueCount) governance requirement(s) are still blocking board readiness.",
                isComplete: governanceIssueCount == 0
            ),
            BoardReadinessItem(
                title: "Thresholds and response",
                detail: record.thresholds.status == .notEvaluated
                    ? "Target bands still need to be evaluated for this package."
                    : boardIssues.contains(where: { $0.localizedCaseInsensitiveContains("Threshold") || $0.localizedCaseInsensitiveContains("target band") })
                        ? (boardIssues.first(where: { $0.localizedCaseInsensitiveContains("Threshold") || $0.localizedCaseInsensitiveContains("target band") }) ?? "Threshold requirements are incomplete.")
                        : "\(record.thresholds.totalTargets) target band(s) evaluated with status \(record.thresholds.status.displayName).",
                isComplete: !boardIssues.contains(where: { $0.localizedCaseInsensitiveContains("Threshold") || $0.localizedCaseInsensitiveContains("target band") })
            ),
            BoardReadinessItem(
                title: "Financial review and provenance",
                detail: boardIssues.isEmpty
                    ? "Finance review and disclosure provenance are complete."
                    : (boardIssues.first(where: { $0.localizedCaseInsensitiveContains("Financial") || $0.localizedCaseInsensitiveContains("Finance") || $0.localizedCaseInsensitiveContains("provenance") }) ?? "Finance or provenance requirements are still blocking board readiness."),
                isComplete: financeIssueCount == 0 && record.provenance.isComplete
            )
        ]
    }

    private func packageComparisonEvidence(for record: TCFDReviewRecord) -> some View {
        let baseline = record.scenario.baselineScenarioName ?? "Baseline not set"
        let comparator = record.scenario.comparatorScenarioName ?? "Comparator not set"
        let baselineRun = record.scenario.baselineRunID ?? "Missing"
        let comparatorRun = record.scenario.comparatorRunID ?? "Missing"
        let summary = [
            record.scenario.shortTermDeltaSummary,
            record.scenario.mediumTermDeltaSummary,
            record.scenario.longTermDeltaSummary
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? "Comparison context is ready, but no delta summary has been written yet."

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comparative Scenario Evidence")
                        .font(.subheadline.weight(.semibold))
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.scenario.resilienceConclusion?.isEmpty == false ? "Conclusion captured" : "Conclusion pending")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 999).fill(Color.secondary.opacity(0.10)))
            }

            HStack(spacing: 8) {
                dashboardChip(label: "Baseline", value: "\(baseline) • \(baselineRun)", tone: .neutral)
                dashboardChip(label: "Comparator", value: "\(comparator) • \(comparatorRun)", tone: .neutral)
                dashboardChip(label: "Delta", value: record.scenario.resilienceConclusion?.isEmpty == false ? "Narrative ready" : "Narrative pending", tone: record.scenario.resilienceConclusion?.isEmpty == false ? .good : .warn)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor).opacity(0.56)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func packageBlockingSummary(blockers: [String]) -> some View {
        Group {
            if blockers.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No blocking issues")
                            .font(.subheadline.weight(.semibold))
                        Text("This package has no remaining validator blockers for its current stage.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.08)))
            } else {
                DisclosureGroup("Top blocking issues (\(blockers.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.orange)
                                Text(blocker)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor).opacity(0.58)))
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func tone(for status: ReviewStatus?) -> DashboardTone {
        switch status {
        case .approved?, .approvedWithConditions?, .boardPackReady?:
            return .good
        case .changesRequested?, .rejected?:
            return .critical
        case .managementReview?, .riskOwnerReview?, .analystReview?:
            return .warn
        default:
            return .neutral
        }
    }

    private func tone(for state: PackageLifecycleState?) -> DashboardTone {
        switch state {
        case .readyForBoard?:
            return .good
        case .readyForReview?, .reviewRecordComplete?, .provenanceComplete?, .financialsCaptured?, .thresholdsEvaluated?:
            return .warn
        default:
            return .neutral
        }
    }

    private func tone(for decision: ReviewDecision?) -> DashboardTone {
        switch decision {
        case .approve?, .approveWithConditions?:
            return .good
        case .requestChanges?:
            return .warn
        case .reject?:
            return .critical
        default:
            return .neutral
        }
    }

    private func tone(for severity: EscalationSeverity?) -> DashboardTone {
        switch severity {
        case .critical?:
            return .critical
        case .material?, .warning?:
            return .warn
        default:
            return .neutral
        }
    }

    private func tone(for status: ThresholdEvaluationStatus) -> DashboardTone {
        switch status {
        case .withinTolerance:
            return .good
        case .nearLimit:
            return .warn
        case .breached:
            return .critical
        case .notEvaluated:
            return .neutral
        }
    }

    private func tone(for status: FinancialEffectsStatus) -> DashboardTone {
        switch status {
        case .quantified:
            return .good
        case .qualitativeOnly, .indicativeRange:
            return .warn
        case .notStarted:
            return .critical
        }
    }

    private func ensureSelectedReviewSnapshot() {
        reviewStore.ensureSelectedReviewSnapshotExists(
            scenario: scenarioStore.selectedScenario,
            governance: scenarioStore.governanceMetadata,
            targetBands: scenarioStore.targetBands
        )
        reviewDraft = reviewStore.selectedBundle?.reviewRecord
    }

    private func syncSelectedReviewSnapshot() {
        reviewStore.syncSelectedReviewSnapshot(
            scenario: scenarioStore.selectedScenario,
            governance: scenarioStore.governanceMetadata,
            targetBands: scenarioStore.targetBands
        )
        reviewDraft = reviewStore.selectedBundle?.reviewRecord
        if let runID = reviewStore.selectedBundle?.runID {
            statusMessage = "Snapshot synced for \(runID)."
        } else {
            statusMessage = "Snapshot synced."
        }
    }

    private var exportBoardPackAvailability: ActionAvailability {
        guard let selected = reviewStore.selectedBundle else {
            return .unavailable("Select a disclosure package first.")
        }
        let record = reviewDraft ?? selected.reviewRecord
        guard let record else {
            return .unavailable("Create or load a review record before exporting a board pack.")
        }
        guard record.reviewStatus == .approved || record.reviewStatus == .approvedWithConditions else {
            return .unavailable("Approve the package before exporting the final board pack.")
        }
        let issues = reviewStore.approvalIssues(for: record)
        guard issues.isEmpty else {
            return .unavailable(issues.first ?? "Resolve board-readiness issues before exporting the board pack.")
        }
        return .ready
    }

    private func uniqueIssues(_ issues: [String]) -> [String] {
        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    private var selectedBoardPackAvailability: ActionAvailability {
        guard let selected = reviewStore.selectedBundle,
              let path = reviewStore.boardPackReportURL(for: selected.runID)?.path else {
            return .unavailable("Select a disclosure package first.")
        }
        return AppActionSupport.pathAvailability(
            path: path,
            expectation: .file,
            emptyReason: "Export the final board pack after approval.",
            missingReason: "The approved board-pack file cannot be found on disk."
        )
    }

    private func exportSelectedBoardPack(openAfterExport: Bool) {
        guard let selected = reviewStore.selectedBundle else { return }
        if let reviewDraft {
            reviewStore.upsertReviewRecord(reviewDraft)
        }
        do {
            let reportURL = try reviewStore.exportBoardPack(for: selected.runID)
            reviewStore.refreshFromDisk()
            statusMessage = "Exported approved board pack for \(selected.runID)."
            if openAfterExport {
                _ = AppActionSupport.openExistingPath(reportURL.path, expectation: .file)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct DashboardStatus {
    let title: String
    let detail: String
    let tone: DashboardTone
}

private struct WildfireImpactDriver: Identifiable {
    let id = UUID()
    let category: String
    let title: String
    let detail: String
    let tone: DashboardTone
}

private struct BoardReadinessItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
}

private enum DashboardTone {
    case good
    case warn
    case critical
    case neutral

    var color: Color {
        switch self {
        case .good:
            return .green
        case .warn:
            return .orange
        case .critical:
            return .red
        case .neutral:
            return .secondary
        }
    }

    var fill: Color {
        color.opacity(0.12)
    }
}

private extension GovernanceAccountabilitySnapshot {
    func setting(boardCommittee: String?) -> GovernanceAccountabilitySnapshot {
        var copy = self
        copy.boardCommittee = boardCommittee
        return copy
    }

    func setting(reviewCadence: String?) -> GovernanceAccountabilitySnapshot {
        var copy = self
        copy.reviewCadence = reviewCadence
        return copy
    }

    func setting(boardOversightRequired: Bool) -> GovernanceAccountabilitySnapshot {
        var copy = self
        copy.boardOversightRequired = boardOversightRequired
        return copy
    }

    func setting(delegatedAuthoritySummary: String?) -> GovernanceAccountabilitySnapshot {
        var copy = self
        copy.delegatedAuthoritySummary = delegatedAuthoritySummary
        return copy
    }

    func setting(ermLinkageSummary: String?) -> GovernanceAccountabilitySnapshot {
        var copy = self
        copy.ermLinkageSummary = ermLinkageSummary
        return copy
    }
}

private struct TCFDDashboardGovernanceEditor: View {
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

private struct TCFDReviewRecordEditor: View {
    let reviewStore: TCFDReviewStore
    @Binding var record: TCFDReviewRecord
    var onSave: () -> Void
    @State private var workflowMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Workflow")
                .font(.headline)

            HStack {
                infoChip(title: "Review Status", value: record.reviewStatus.displayName)
                infoChip(title: "Package State", value: record.packageState.displayName)
                infoChip(title: "Decision", value: record.decision.displayName)
                infoChip(title: "Escalation", value: record.escalationSeverity.displayName)
            }

            workflowStageActions

            if let workflowMessage {
                Text(workflowMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                personField("Current owner", person: binding(for: \.currentOwner))
                personField("Approver", person: binding(for: \.approver))
            }

            HStack {
                requiredPersonField("Prepared by", person: Binding(
                    get: { record.preparedBy },
                    set: { record.preparedBy = $0 }
                ))
                personField("Executive owner", person: binding(for: \.accountableExecutive))
            }

            DatePicker("Due date", selection: dueDateBinding, displayedComponents: .date)

            VStack(alignment: .leading, spacing: 10) {
                Text("Governance Accountability")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    TextField("Board committee", text: optionalStringBinding(
                        get: { record.governance?.boardCommittee },
                        set: { record.governance = governanceSnapshot().setting(boardCommittee: $0) }
                    ))
                    TextField("Review cadence", text: optionalStringBinding(
                        get: { record.governance?.reviewCadence },
                        set: { record.governance = governanceSnapshot().setting(reviewCadence: $0) }
                    ))
                }
                HStack {
                    personField("Management owner", person: governancePersonBinding(\.managementOwner))
                    personField("Risk owner", person: governancePersonBinding(\.riskOwner))
                }
                HStack {
                    personField("Finance reviewer", person: governancePersonBinding(\.financeReviewer))
                    Toggle("Board oversight required", isOn: governanceBoolBinding(
                        get: { record.governance?.boardOversightRequired ?? true },
                        set: { record.governance = governanceSnapshot().setting(boardOversightRequired: $0) }
                    ))
                }
                TextField("Delegated authority summary", text: optionalStringBinding(
                    get: { record.governance?.delegatedAuthoritySummary },
                    set: { record.governance = governanceSnapshot().setting(delegatedAuthoritySummary: $0) }
                ), axis: .vertical)
                .lineLimit(2...4)
                TextField("ERM linkage summary", text: optionalStringBinding(
                    get: { record.governance?.ermLinkageSummary },
                    set: { record.governance = governanceSnapshot().setting(ermLinkageSummary: $0) }
                ), axis: .vertical)
                .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Scenario Context")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    TextField("Scenario name", text: Binding(
                        get: { record.scenario.scenarioName },
                        set: { record.scenario.scenarioName = $0 }
                    ))
                    TextField("Scenario label", text: Binding(
                        get: { record.scenario.tcfdScenarioLabel },
                        set: { record.scenario.tcfdScenarioLabel = $0 }
                    ))
                }
                HStack {
                    TextField("Short horizon", text: optionalStringBinding(
                        get: { record.scenario.shortHorizonLabel },
                        set: { record.scenario.shortHorizonLabel = $0 }
                    ))
                    TextField("Medium horizon", text: optionalStringBinding(
                        get: { record.scenario.mediumHorizonLabel },
                        set: { record.scenario.mediumHorizonLabel = $0 }
                    ))
                    TextField("Long horizon", text: optionalStringBinding(
                        get: { record.scenario.longHorizonLabel },
                        set: { record.scenario.longHorizonLabel = $0 }
                    ))
                }
                HStack {
                    TextField("Baseline scenario", text: optionalStringBinding(
                        get: { record.scenario.baselineScenarioName },
                        set: { record.scenario.baselineScenarioName = $0 }
                    ))
                    TextField("Comparator scenario", text: optionalStringBinding(
                        get: { record.scenario.comparatorScenarioName },
                        set: { record.scenario.comparatorScenarioName = $0 }
                    ))
                }
                HStack {
                    comparisonRunPicker(title: "Baseline package",
                                        selection: optionalStringBinding(
                                            get: { record.scenario.baselineRunID },
                                            set: { record.scenario.baselineRunID = $0 }
                                        ),
                                        includeCurrentRun: true)
                    comparisonRunPicker(title: "Comparator package",
                                        selection: optionalStringBinding(
                                            get: { record.scenario.comparatorRunID },
                                            set: { record.scenario.comparatorRunID = $0 }
                                        ),
                                        includeCurrentRun: false)
                }
                HStack {
                    TextField("Baseline run ID", text: optionalStringBinding(
                        get: { record.scenario.baselineRunID },
                        set: { record.scenario.baselineRunID = $0 }
                    ))
                    TextField("Comparator run ID", text: optionalStringBinding(
                        get: { record.scenario.comparatorRunID },
                        set: { record.scenario.comparatorRunID = $0 }
                    ))
                }
                TextField("Short-term delta summary", text: optionalStringBinding(
                    get: { record.scenario.shortTermDeltaSummary },
                    set: { record.scenario.shortTermDeltaSummary = $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
                TextField("Medium-term delta summary", text: optionalStringBinding(
                    get: { record.scenario.mediumTermDeltaSummary },
                    set: { record.scenario.mediumTermDeltaSummary = $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
                TextField("Long-term delta summary", text: optionalStringBinding(
                    get: { record.scenario.longTermDeltaSummary },
                    set: { record.scenario.longTermDeltaSummary = $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
                TextField("Resilience conclusion", text: optionalStringBinding(
                    get: { record.scenario.resilienceConclusion },
                    set: { record.scenario.resilienceConclusion = $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
                TextField("Wildfire assumptions summary", text: optionalStringBinding(
                    get: { record.scenario.wildfireAssumptionsSummary },
                    set: { record.scenario.wildfireAssumptionsSummary = $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
            }

            HStack {
                reviewPicker("Threshold status", selection: $record.thresholds.status)
                reviewPicker("Financial effects", selection: $record.financialEffects.status)
            }

            thresholdBreachActionsSection

            Toggle("Finance reviewed", isOn: $record.financialEffects.financeReviewed)

            TextField("Financial effects summary", text: $record.financialEffects.planningImpactSummary, axis: .vertical)
                .lineLimit(2...4)
            HStack {
                TextField("Magnitude band", text: optionalStringBinding(
                    get: { record.financialEffects.magnitudeBand },
                    set: { record.financialEffects.magnitudeBand = $0 }
                ))
                TextField("Methodology note", text: optionalStringBinding(
                    get: { record.financialEffects.methodologyNote },
                    set: { record.financialEffects.methodologyNote = $0 }
                ))
            }
            HStack {
                TextField("Currency", text: optionalStringBinding(
                    get: { record.financialEffects.currencyCode },
                    set: { record.financialEffects.currencyCode = $0 }
                ))
                TextField("Exposure value", text: optionalDoubleStringBinding(
                    get: { record.financialEffects.exposureValue },
                    set: { record.financialEffects.exposureValue = $0 }
                ))
                TextField("Burn probability proxy", text: optionalDoubleStringBinding(
                    get: { record.financialEffects.burnProbabilityProxy },
                    set: { record.financialEffects.burnProbabilityProxy = $0 }
                ))
            }
            HStack {
                TextField("Vulnerability ratio", text: optionalDoubleStringBinding(
                    get: { record.financialEffects.vulnerabilityRatio },
                    set: { record.financialEffects.vulnerabilityRatio = $0 }
                ))
                TextField("Deductible %", text: optionalDoubleStringBinding(
                    get: { record.financialEffects.deductiblePct.map { $0 * 100 } },
                    set: { record.financialEffects.deductiblePct = $0.map { $0 / 100 } }
                ))
                TextField("Limit %", text: optionalDoubleStringBinding(
                    get: { record.financialEffects.limitPct.map { $0 * 100 } },
                    set: { record.financialEffects.limitPct = $0.map { $0 / 100 } }
                ))
            }
            if record.financialEffects.estimatedGroundUpLoss != nil || record.financialEffects.estimatedInsuredLoss != nil {
                HStack {
                    infoChip(title: "Indicative GUL", value: formattedFinancialValue(record.financialEffects.estimatedGroundUpLoss, currencyCode: record.financialEffects.currencyCode))
                    infoChip(title: "Indicative IL", value: formattedFinancialValue(record.financialEffects.estimatedInsuredLoss, currencyCode: record.financialEffects.currencyCode))
                }
            }

            TextField("Conditions (one per line)", text: conditionsTextBinding, axis: .vertical)
                .lineLimit(2...4)

            TextField("Reviewer notes", text: $record.reviewerNotes, axis: .vertical)
                .lineLimit(3...6)

            HStack {
                infoChip(title: "Scenario", value: record.scenario.tcfdScenarioLabel)
                infoChip(title: "Thresholds", value: "\(record.thresholds.breachedCount) breached")
                infoChip(title: "Finance", value: record.financialEffects.status.displayName)
                infoChip(title: "Provenance", value: record.provenance.isComplete ? "Complete" : "Incomplete")
            }

            Button("Save Review Workflow") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var workflowStageActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workflow Actions")
                .font(.subheadline.weight(.semibold))

            HStack {
                workflowActionButton("Submit for Analyst Review", targetStatus: .analystReview)
                workflowActionButton("Send to Risk Owner", targetStatus: .riskOwnerReview)
                workflowActionButton("Send to Management", targetStatus: .managementReview)
            }

            HStack {
                workflowActionButton("Mark Board Pack Ready", targetStatus: .boardPackReady)
                workflowActionButton("Approve", targetStatus: .approved)
                workflowActionButton("Approve With Conditions", targetStatus: .approvedWithConditions)
            }

            HStack {
                workflowActionButton("Request Changes", targetStatus: .changesRequested)
                workflowActionButton("Reject", targetStatus: .rejected)
                workflowActionButton("Reset to Packaged", targetStatus: .packaged)
            }
        }
    }

    private func personField(_ label: String, person: Binding<PersonRef?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("\(label) name", text: Binding(
                get: { person.wrappedValue?.name ?? "" },
                set: { newValue in
                    var current = person.wrappedValue ?? PersonRef(name: "", title: "")
                    current.name = newValue
                    person.wrappedValue = current.isEmpty ? nil : current
                }
            ))
            TextField("\(label) title", text: Binding(
                get: { person.wrappedValue?.title ?? "" },
                set: { newValue in
                    var current = person.wrappedValue ?? PersonRef(name: "", title: "")
                    current.title = newValue
                    person.wrappedValue = current.isEmpty ? nil : current
                }
            ))
        }
    }

    private func requiredPersonField(_ label: String, person: Binding<PersonRef>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("\(label) name", text: Binding(
                get: { person.wrappedValue.name },
                set: {
                    var current = person.wrappedValue
                    current.name = $0
                    person.wrappedValue = current
                }
            ))
            TextField("\(label) title", text: Binding(
                get: { person.wrappedValue.title },
                set: {
                    var current = person.wrappedValue
                    current.title = $0
                    person.wrappedValue = current
                }
            ))
        }
    }

    private func binding(for keyPath: WritableKeyPath<TCFDReviewRecord, PersonRef?>) -> Binding<PersonRef?> {
        Binding(
            get: { record[keyPath: keyPath] },
            set: { record[keyPath: keyPath] = $0 }
        )
    }

    private func governancePersonBinding(_ keyPath: WritableKeyPath<GovernanceAccountabilitySnapshot, PersonRef?>) -> Binding<PersonRef?> {
        Binding(
            get: { record.governance?[keyPath: keyPath] },
            set: { newValue in
                var snapshot = governanceSnapshot()
                snapshot[keyPath: keyPath] = newValue
                record.governance = snapshot
            }
        )
    }

    private func governanceBoolBinding(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: set)
    }

    private func optionalStringBinding(get: @escaping () -> String?, set: @escaping (String?) -> Void) -> Binding<String> {
        Binding(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    private func optionalDoubleStringBinding(get: @escaping () -> Double?, set: @escaping (Double?) -> Void) -> Binding<String> {
        Binding(
            get: {
                guard let value = get() else { return "" }
                return String(format: value.rounded() == value ? "%.0f" : "%.4f", value)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    set(nil)
                    return
                }
                set(Double(trimmed))
            }
        )
    }

    private func formattedFinancialValue(_ value: Double?, currencyCode: String?) -> String {
        guard let value else { return "Pending" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        if let currencyCode, !currencyCode.isEmpty {
            return "\(currencyCode) \(amount)"
        }
        return amount
    }

    private func governanceSnapshot() -> GovernanceAccountabilitySnapshot {
        record.governance ?? GovernanceAccountabilitySnapshot()
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { record.dueDate ?? Date() },
            set: { record.dueDate = $0 }
        )
    }

    private var conditionsTextBinding: Binding<String> {
        Binding(
            get: { record.conditions.joined(separator: "\n") },
            set: { newValue in
                record.conditions = newValue
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func reviewPicker<Value>(_ title: String, selection: Binding<Value>) -> some View where Value: CaseIterable & Identifiable & Hashable, Value: RawRepresentable, Value.RawValue == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(Array(Value.allCases), id: \.id) { value in
                    Text(displayName(for: value)).tag(value)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonRunPicker(title: String,
                                     selection: Binding<String>,
                                     includeCurrentRun: Bool) -> some View {
        let candidates = includeCurrentRun ? reviewStore.bundles : reviewStore.comparisonCandidates(excluding: record.runID)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("Not selected").tag("")
                ForEach(candidates, id: \.runID) { bundle in
                    let scenarioName = bundle.scenarioName ?? bundle.tcfdScenarioLabel ?? bundle.runID
                    Text("\(bundle.runID) • \(scenarioName)").tag(bundle.runID)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayName<Value>(for value: Value) -> String where Value: RawRepresentable, Value.RawValue == String {
        switch value {
        case let status as ReviewStatus:
            return status.displayName
        case let state as PackageLifecycleState:
            return state.displayName
        case let decision as ReviewDecision:
            return decision.displayName
        case let severity as EscalationSeverity:
            return severity.displayName
        case let threshold as ThresholdEvaluationStatus:
            return threshold.displayName
        case let financial as FinancialEffectsStatus:
            return financial.displayName
        case let response as BreachResponseType:
            return response.displayName
        case let status as BreachActionStatus:
            return status.displayName
        default:
            return value.rawValue
        }
    }

    private func infoChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.medium))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor).opacity(0.60)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    private func workflowActionButton(_ title: String, targetStatus: ReviewStatus) -> some View {
        let availability = reviewStore.workflowAvailability(for: targetStatus, record: record)
        return Button(title) {
            record = reviewStore.transitionedReviewRecord(record, to: targetStatus)
            workflowMessage = "Workflow moved to \(record.reviewStatus.displayName)."
            onSave()
        }
        .buttonStyle(.bordered)
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? title)
    }

    @ViewBuilder
    private var thresholdBreachActionsSection: some View {
        let breachedEvaluations = record.thresholds.evaluations.filter { $0.status == .breached }
        if !breachedEvaluations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Threshold Breach Actions")
                    .font(.subheadline.weight(.semibold))

                Text("Each breached metric needs an owner, due date, impact summary, and management rationale before the package can become board-ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(breachedActionBindings.enumerated()), id: \.offset) { index, actionBinding in
                    thresholdBreachActionEditor(action: actionBinding,
                                                fallbackMetricName: breachedEvaluations[index].metricName)
                }
            }
        }
    }

    private var breachedActionBindings: [Binding<ThresholdBreachAction>] {
        let requiredCount = record.thresholds.evaluations.filter { $0.status == .breached }.count
        if (record.thresholdBreachActions ?? []).count < requiredCount {
            let currentActions = record.thresholdBreachActions ?? []
            let existingMetrics = Set(currentActions.map(\.metricName))
            let newActions = record.thresholds.evaluations
                .filter { $0.status == .breached && !existingMetrics.contains($0.metricName) }
                .map {
                    ThresholdBreachAction(
                        metricName: $0.metricName,
                        breachSummary: "\($0.metricName) exceeded \($0.thresholdDisplayValue) with \($0.observedDisplayValue).",
                        businessImpactSummary: "",
                        responseType: .mitigate,
                        actionOwner: nil,
                        targetDate: nil,
                        status: .open,
                        managementRationale: ""
                    )
                }
            record.thresholdBreachActions = currentActions + newActions
        }

        return (record.thresholdBreachActions ?? []).indices.map { index in
            Binding(
                get: { (record.thresholdBreachActions ?? [])[index] },
                set: { newValue in
                    guard var actions = record.thresholdBreachActions, actions.indices.contains(index) else { return }
                    actions[index] = newValue
                    record.thresholdBreachActions = actions
                }
            )
        }
    }

    private func thresholdBreachActionEditor(action: Binding<ThresholdBreachAction>,
                                             fallbackMetricName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.wrappedValue.metricName.isEmpty ? fallbackMetricName : action.wrappedValue.metricName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                reviewPicker("Response", selection: Binding(
                    get: { action.wrappedValue.responseType },
                    set: { action.wrappedValue.responseType = $0 }
                ))
                reviewPicker("Status", selection: Binding(
                    get: { action.wrappedValue.status },
                    set: { action.wrappedValue.status = $0 }
                ))
            }

            TextField("Breach summary", text: Binding(
                get: { action.wrappedValue.breachSummary },
                set: { action.wrappedValue.breachSummary = $0 }
            ), axis: .vertical)
            .lineLimit(2...3)

            TextField("Business impact summary", text: Binding(
                get: { action.wrappedValue.businessImpactSummary },
                set: { action.wrappedValue.businessImpactSummary = $0 }
            ), axis: .vertical)
            .lineLimit(2...4)

            HStack {
                personField("Action owner", person: Binding(
                    get: { action.wrappedValue.actionOwner },
                    set: { action.wrappedValue.actionOwner = $0 }
                ))
                DatePicker("Target date",
                           selection: Binding(
                            get: { action.wrappedValue.targetDate ?? Date() },
                            set: { action.wrappedValue.targetDate = $0 }
                           ),
                           displayedComponents: .date)
            }

            TextField("Management rationale", text: Binding(
                get: { action.wrappedValue.managementRationale },
                set: { action.wrappedValue.managementRationale = $0 }
            ), axis: .vertical)
            .lineLimit(2...4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor).opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }
}
