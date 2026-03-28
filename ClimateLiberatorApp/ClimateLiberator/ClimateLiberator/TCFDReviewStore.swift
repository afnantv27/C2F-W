import Foundation
import SwiftUI
import Combine

final class TCFDReviewStore: ObservableObject {
    @Published private(set) var bundles: [TCFDRunArtifactBundle] = []
    @Published var selectedBundleID: String?
    @Published private(set) var discoveryStatus = "Package discovery idle."

    private let storageURL: URL
    private let encoder = JSONEncoder()
    private var additionalRoots: [URL] = []
    private let discoveryQueue = DispatchQueue(label: "com.climateliberator.tcfdreview.discovery", qos: .utility)
    private var discoveryGeneration: UInt = 0
    private let bundleCache: TCFDBundleCache
    private let workflowPolicy: TCFDReviewWorkflowPolicying
    private let discoveryService: TCFDReviewDiscoveryServicing
    private let persistenceService: TCFDReviewPersistenceServicing
    private let exportService: TCFDBoardPackExportServicing

    init(storageURL: URL? = nil,
         workflowPolicy: TCFDReviewWorkflowPolicying = TCFDReviewWorkflowPolicy(),
         discoveryService: TCFDReviewDiscoveryServicing = TCFDReviewDiscoveryService(),
         persistenceService: TCFDReviewPersistenceServicing = TCFDReviewPersistenceService(),
         exportService: TCFDBoardPackExportServicing = TCFDBoardPackExportService(),
         bundleCache: TCFDBundleCache = TCFDBundleCache()) {
        self.storageURL = storageURL ?? TCFDReviewStore.defaultStorageURL()
        self.discoveryService = discoveryService
        self.persistenceService = persistenceService
        self.exportService = exportService
        self.bundleCache = bundleCache
        self.workflowPolicy = workflowPolicy
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        reload()
    }

    var selectedBundle: TCFDRunArtifactBundle? {
        bundles.first { $0.id == selectedBundleID }
    }

    func reload() {
        discoveryGeneration &+= 1
        let generation = discoveryGeneration
        let roots = uniqueRoots(candidateRoots() + additionalRoots)
        let startedAt = Date()
        discoveryQueue.async { [weak self] in
            guard let self else { return }
            let outcome = self.discoveryService.discoverBundles(
                in: roots,
                cache: self.bundleCache,
                defaultReviewRecord: { [weak self] in self?.defaultReviewRecord(for: $0) ?? .placeholder },
                normalizeReviewRecord: { [weak self] in self?.normalizedReviewRecord($0) ?? $0 },
                reviewRecordNeedsRepair: { [weak self] in self?.reviewRecordNeedsRepair($0) ?? false }
            )
            let duration = Date().timeIntervalSince(startedAt)
            DispatchQueue.main.async {
                guard generation == self.discoveryGeneration else { return }
                let bundlesChanged = outcome.bundles != self.bundles
                self.bundles = outcome.bundles
                if self.selectedBundleID == nil {
                    self.selectedBundleID = outcome.bundles.first?.id
                } else if !outcome.bundles.contains(where: { $0.id == self.selectedBundleID }) {
                    self.selectedBundleID = outcome.bundles.first?.id
                }
                if bundlesChanged {
                    self.persistIndex()
                }
                self.discoveryStatus = self.makeDiscoveryStatus(outcome: outcome, duration: duration)
            }
        }
    }

    func updateDiscoveryRoots(_ roots: [URL]) {
        let normalizedRoots = uniqueRoots(roots)
        guard normalizedRoots != additionalRoots else { return }
        additionalRoots = normalizedRoots
        reload()
    }

    func bundle(for runID: String) -> TCFDRunArtifactBundle? {
        bundles.first { $0.runID == runID }
    }

    func selectBundle(id: String?) {
        selectedBundleID = id
    }

    func comparisonCandidates(excluding runID: String? = nil) -> [TCFDRunArtifactBundle] {
        bundles.filter { bundle in
            guard let runID else { return true }
            return bundle.runID != runID
        }
    }

    func boardPackReportURL(for runID: String) -> URL? {
        guard let bundle = bundle(for: runID) else { return nil }
        return URL(fileURLWithPath: bundle.bundleURL).appendingPathComponent("tcfd_board_pack.md")
    }

    func exportBoardPack(for runID: String) throws -> URL {
        guard let bundle = bundle(for: runID),
              let review = bundle.reviewRecord else {
            throw ExportError.missingBundle
        }
        guard review.reviewStatus == .approved || review.reviewStatus == .approvedWithConditions else {
            throw ExportError.notApproved
        }

        let report = makeBoardPackReport(bundle: bundle, review: review)
        let reportURL = try exportService.exportBoardPack(bundle: bundle,
                                                          review: review,
                                                          report: report,
                                                          encoder: encoder)

        var exportedReview = review
        exportedReview.reviewEvents = appendedReviewEvent(
            existing: exportedReview.reviewEvents,
            action: "Board pack exported",
            status: exportedReview.reviewStatus,
            note: reportURL.lastPathComponent
        )
        upsertReviewRecord(exportedReview)

        return reportURL
    }

    func upsertReviewRecord(_ record: TCFDReviewRecord) {
        guard let index = bundles.firstIndex(where: { $0.runID == record.runID }) else { return }
        var updatedRecord = normalizedReviewRecord(record)
        updatedRecord.updatedAt = Date()
        bundles[index].reviewRecord = updatedRecord
        do {
            let reviewURL = URL(fileURLWithPath: bundles[index].reviewRecordURL)
            try persistenceService.persistReviewRecord(updatedRecord, to: reviewURL)
            bundleCache.invalidate(manifestPath: bundles[index].manifestURL)
            persistIndex()
        } catch {
            // Keep in-memory edits even if disk persistence fails.
        }
    }

    func readyForBoardCount() -> Int {
        bundles.filter { $0.reviewRecord?.packageState == .readyForBoard }.count
    }

    func escalatedCount() -> Int {
        bundles.filter {
            guard let severity = $0.reviewRecord?.escalationSeverity else { return false }
            return severity == .material || severity == .critical
        }.count
    }

    func overdueReviewCount(referenceDate: Date = Date()) -> Int {
        bundles.filter {
            guard let dueDate = $0.reviewRecord?.dueDate else { return false }
            return dueDate < referenceDate
        }.count
    }

    func financePendingCount() -> Int {
        bundles.filter {
            guard let review = $0.reviewRecord else { return false }
            return review.financialEffects.status == .notStarted || review.financialEffects.financeReviewed == false
        }.count
    }

    func breachedPackageCount() -> Int {
        bundles.filter {
            guard let thresholds = $0.reviewRecord?.thresholds else { return false }
            return thresholds.status == .breached || thresholds.breachedCount > 0
        }.count
    }

    func workflowAvailability(for targetStatus: ReviewStatus,
                              record: TCFDReviewRecord) -> ActionAvailability {
        switch targetStatus {
        case .packaged:
            return .ready
        case .analystReview:
            let issues = readyForReviewIssues(for: record)
            return issues.isEmpty ? .ready : .unavailable(issues.first ?? "Package is not ready for analyst review.")
        case .riskOwnerReview:
            guard readyForReviewIssues(for: record).isEmpty else {
                return .unavailable("Resolve review-gate issues before sending this package to the risk owner.")
            }
            guard record.currentOwner?.isEmpty == false else {
                return .unavailable("Assign a current review owner before sending this package to the risk owner.")
            }
            return .ready
        case .managementReview:
            guard readyForReviewIssues(for: record).isEmpty else {
                return .unavailable("Resolve review-gate issues before management review.")
            }
            guard thresholdBreachWorkflowIssues(for: record, requireRationale: false).isEmpty else {
                return .unavailable(thresholdBreachWorkflowIssues(for: record, requireRationale: false).first ?? "Document threshold-breach actions before management review.")
            }
            guard record.currentOwner?.isEmpty == false else {
                return .unavailable("Assign a current review owner before management review.")
            }
            guard record.accountableExecutive?.isEmpty == false else {
                return .unavailable("Assign an accountable executive before management review.")
            }
            return .ready
        case .boardPackReady:
            let issues = readyForBoardIssues(for: record)
            return issues.isEmpty ? .ready : .unavailable(issues.first ?? "Board-pack requirements are incomplete.")
        case .approved, .approvedWithConditions:
            let issues = approvalIssues(for: record, requireFinalTimestamps: false)
            guard issues.isEmpty else {
                return .unavailable(issues.first ?? "Resolve approval evidence before recording approval.")
            }
            return .ready
        case .changesRequested:
            guard record.reviewStatus != .approved && record.reviewStatus != .approvedWithConditions && record.reviewStatus != .superseded else {
                return .unavailable("This package is already closed.")
            }
            return .ready
        case .rejected:
            guard record.reviewStatus == .managementReview || record.reviewStatus == .boardPackReady else {
                return .unavailable("Reject after management review or board-pack review has started.")
            }
            return .ready
        case .superseded:
            return .ready
        }
    }

    func transitionedReviewRecord(_ record: TCFDReviewRecord,
                                  to targetStatus: ReviewStatus) -> TCFDReviewRecord {
        var updated = record
        let now = Date()

        switch targetStatus {
        case .packaged:
            updated.reviewStatus = .packaged
            updated.submittedAt = nil
            updated.reviewedAt = nil
            updated.approvedAt = nil
            updated.decision = .none
        case .analystReview:
            updated.reviewStatus = .analystReview
            updated.submittedAt = updated.submittedAt ?? now
            updated.decision = .none
        case .riskOwnerReview:
            updated.reviewStatus = .riskOwnerReview
            updated.submittedAt = updated.submittedAt ?? now
            updated.reviewedAt = now
            updated.decision = .none
        case .managementReview:
            updated.reviewStatus = .managementReview
            updated.submittedAt = updated.submittedAt ?? now
            updated.reviewedAt = now
            updated.decision = .none
        case .boardPackReady:
            updated.reviewStatus = .boardPackReady
            updated.reviewedAt = now
            updated.decision = .none
        case .approved:
            updated.reviewStatus = .approved
            updated.reviewedAt = updated.reviewedAt ?? now
            updated.approvedAt = now
            updated.decision = .approve
        case .approvedWithConditions:
            updated.reviewStatus = .approvedWithConditions
            updated.reviewedAt = updated.reviewedAt ?? now
            updated.approvedAt = now
            updated.decision = .approveWithConditions
        case .changesRequested:
            updated.reviewStatus = .changesRequested
            updated.reviewedAt = now
            updated.approvedAt = nil
            updated.decision = .requestChanges
        case .rejected:
            updated.reviewStatus = .rejected
            updated.reviewedAt = now
            updated.approvedAt = nil
            updated.decision = .reject
        case .superseded:
            updated.reviewStatus = .superseded
        }

        updated.approvalEvidence = transitionedApprovalEvidence(updated.approvalEvidence, for: targetStatus)
        updated.reviewEvents = appendedReviewEvent(
            existing: updated.reviewEvents,
            action: "Workflow moved to \(targetStatus.displayName)",
            status: targetStatus,
            note: nil
        )

        return normalizedReviewRecord(updated)
    }

    func readyForReviewIssues(for record: TCFDReviewRecord) -> [String] {
        workflowPolicy.readyForReviewIssues(for: record)
    }

    func readyForBoardIssues(for record: TCFDReviewRecord) -> [String] {
        workflowPolicy.readyForBoardIssues(for: record, comparisonIssues: comparisonIssues(for: record))
    }

    func comparisonIssues(for record: TCFDReviewRecord) -> [String] {
        var issues: [String] = []

        if stringValue(record.scenario.baselineScenarioName).isEmpty {
            issues.append("Baseline scenario reference is missing.")
        }
        if stringValue(record.scenario.comparatorScenarioName).isEmpty {
            issues.append("Comparator scenario reference is missing.")
        }
        if stringValue(record.scenario.baselineRunID).isEmpty {
            issues.append("Baseline run ID is missing.")
        }
        if stringValue(record.scenario.comparatorRunID).isEmpty {
            issues.append("Comparator run ID is missing.")
        }
        if record.scenario.baselineRunID == record.scenario.comparatorRunID,
           stringValue(record.scenario.baselineRunID).isEmpty == false {
            issues.append("Comparator run must be different from the baseline run.")
        }
        if stringValue(record.scenario.shortTermDeltaSummary).isEmpty {
            issues.append("Short-term scenario delta summary is missing.")
        }
        if stringValue(record.scenario.mediumTermDeltaSummary).isEmpty {
            issues.append("Medium-term scenario delta summary is missing.")
        }
        if stringValue(record.scenario.longTermDeltaSummary).isEmpty {
            issues.append("Long-term scenario delta summary is missing.")
        }
        if stringValue(record.scenario.resilienceConclusion).isEmpty {
            issues.append("Resilience conclusion is missing.")
        }

        if let evidence = resolvedComparisonEvidence(baselineRunID: record.scenario.baselineRunID,
                                                     comparatorRunID: record.scenario.comparatorRunID,
                                                     fallbackBundle: bundle(for: record.runID),
                                                     fallbackReview: record) {
            if !evidence.baselineReview.provenance.isComplete || !evidence.comparatorReview.provenance.isComplete {
                issues.append("Baseline and comparator packages must both have complete provenance.")
            }
            if evidence.baselineBundle.inputFolder != evidence.comparatorBundle.inputFolder {
                issues.append("Baseline and comparator packages must point to the same study scope before comparison can be trusted.")
            }
        } else if !stringValue(record.scenario.baselineRunID).isEmpty && !stringValue(record.scenario.comparatorRunID).isEmpty {
            issues.append("Baseline and comparator package evidence could not be resolved from stored run bundles.")
        }

        return uniqueIssues(issues)
    }

    func approvalIssues(for record: TCFDReviewRecord,
                        requireFinalTimestamps: Bool = true) -> [String] {
        workflowPolicy.approvalIssues(for: record,
                                      readyForBoardIssues: readyForBoardIssues(for: record),
                                      requireFinalTimestamps: requireFinalTimestamps)
    }

    func historyIntegrityIssues(for record: TCFDReviewRecord) -> [String] {
        workflowPolicy.historyIntegrityIssues(for: record)
    }

    private func uniqueRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.compactMap { root in
            let standardized = root.standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    func persistIndex() {
        persistenceService.persistIndex(TCFDReviewBundleIndex(bundles: bundles, updatedAt: Date()),
                                        to: storageURL)
    }

    func refreshFromDisk() {
        reload()
    }

    private func makeDiscoveryStatus(outcome: TCFDDiscoveryOutcome, duration: TimeInterval) -> String {
        let durationText = String(format: "%.2fs", duration)
        if outcome.bundles.isEmpty {
            if outcome.skippedReviewRecordCount > 0 || outcome.repairedReviewRecordCount > 0 {
                return "No packages discovered. Repaired \(outcome.repairedReviewRecordCount) review record(s), skipped \(outcome.skippedReviewRecordCount) malformed record(s) in \(durationText)."
            }
            return "No packages discovered. Last reload completed in \(durationText)."
        }

        var parts = ["\(outcome.bundles.count) package(s) loaded in \(durationText)"]
        if outcome.repairedReviewRecordCount > 0 {
            parts.append("\(outcome.repairedReviewRecordCount) review record(s) normalized")
        }
        if outcome.skippedReviewRecordCount > 0 {
            parts.append("\(outcome.skippedReviewRecordCount) malformed review record(s) skipped")
        }
        return parts.joined(separator: " • ")
    }

    func ensureSelectedReviewSnapshotExists(scenario: ScenarioDefinition?,
                                            governance: GovernanceMetadata,
                                            targetBands: [TargetBand]) {
        guard let runID = selectedBundleID ?? bundles.first?.runID else { return }
        ensureReviewSnapshotExists(for: runID,
                                   scenario: scenario,
                                   governance: governance,
                                   targetBands: targetBands)
    }

    func ensureReviewSnapshotExists(for runID: String,
                                    scenario: ScenarioDefinition?,
                                    governance: GovernanceMetadata,
                                    targetBands: [TargetBand]) {
        guard let bundle = bundle(for: runID) else { return }
        let reviewURL = URL(fileURLWithPath: bundle.reviewRecordURL)
        guard !FileManager.default.fileExists(atPath: reviewURL.path) else { return }
        syncReviewSnapshot(for: runID,
                           scenario: scenario,
                           governance: governance,
                           targetBands: targetBands)
    }

    func syncSelectedReviewSnapshot(scenario: ScenarioDefinition?,
                                    governance: GovernanceMetadata,
                                    targetBands: [TargetBand]) {
        guard let runID = selectedBundleID ?? bundles.first?.runID else { return }
        syncReviewSnapshot(for: runID,
                           scenario: scenario,
                           governance: governance,
                           targetBands: targetBands)
    }

    func syncReviewSnapshot(for runID: String,
                            scenario: ScenarioDefinition?,
                            governance: GovernanceMetadata,
                            targetBands: [TargetBand]) {
        guard let index = bundles.firstIndex(where: { $0.runID == runID }) else { return }

        let bundle = bundles[index]
        var record = bundles[index].reviewRecord ?? defaultReviewRecord(for: bundle)

        record.scenario = buildScenarioSnapshot(for: bundle, scenario: scenario, existing: record.scenario)
        record.governance = buildGovernanceSnapshot(from: governance, existing: record.governance, record: record)
        record.thresholds = evaluateThresholds(for: bundle, targetBands: targetBands)
        record.impactDrivers = buildImpactDrivers(for: bundle,
                                                 scenario: scenario,
                                                 thresholds: record.thresholds,
                                                 financialEffects: record.financialEffects,
                                                 existing: record.impactDrivers)
        record.roadmapStages = buildRoadmapStages(for: bundle,
                                                  record: record,
                                                  targetBands: targetBands)
        record.packageState = recommendedPackageState(for: record)
        upsertReviewRecord(record)
    }

    func autoPrepareSelectedReview(scenario: ScenarioDefinition?,
                                   governance: GovernanceMetadata,
                                   targetBands: [TargetBand]) {
        syncSelectedReviewSnapshot(scenario: scenario,
                                   governance: governance,
                                   targetBands: targetBands)
    }

    func autoPrepareReview(for runID: String,
                           scenario: ScenarioDefinition?,
                           governance: GovernanceMetadata,
                           targetBands: [TargetBand]) {
        syncReviewSnapshot(for: runID,
                           scenario: scenario,
                           governance: governance,
                           targetBands: targetBands)
    }

    private func defaultReviewRecord(for bundle: TCFDRunArtifactBundle) -> TCFDReviewRecord {
        normalizedReviewRecord(
            TCFDReviewRecord(
                runID: bundle.runID,
                bundleID: bundle.id,
                reviewStatus: .packaged,
                packageState: .generated,
                decision: .none,
                escalationSeverity: .warning,
                preparedBy: PersonRef(name: "Climate Liberator Analyst", title: "Prepared Automatically"),
                currentOwner: nil,
                accountableExecutive: nil,
                approver: nil,
                dueDate: Calendar.current.date(byAdding: .day, value: 7, to: bundle.timestamp),
                preparedAt: bundle.generatedAt,
                submittedAt: nil,
                reviewedAt: nil,
                approvedAt: nil,
                updatedAt: bundle.generatedAt,
                governance: GovernanceAccountabilitySnapshot(
                    boardCommittee: "Board / ESG Committee",
                    boardOversightRequired: true,
                    managementOwner: nil,
                    riskOwner: nil,
                    financeReviewer: nil,
                    reviewCadence: "Quarterly or event-driven",
                    delegatedAuthoritySummary: "",
                    ermLinkageSummary: "Wildfire review should flow into the corporate ERM register and board reporting pack."
                ),
                scenario: ReviewScenarioSnapshot(
                    scenarioName: bundle.scenarioName ?? bundle.runID,
                    tcfdScenarioLabel: bundle.tcfdScenarioLabel ?? bundle.simulatorLabel,
                    simulatorLabel: bundle.simulatorLabel,
                    shortHorizonLabel: bundle.scenarioHorizon ?? "0-3 years",
                    mediumHorizonLabel: "3-10 years",
                    longHorizonLabel: "10+ years",
                    baselineScenarioName: bundle.scenarioName ?? bundle.simulatorLabel,
                    comparatorScenarioName: bundle.scenarioPathway,
                    baselineRunID: bundle.runID,
                    comparatorRunID: nil,
                    shortTermDeltaSummary: "",
                    mediumTermDeltaSummary: "",
                    longTermDeltaSummary: "",
                    resilienceConclusion: "",
                    wildfireAssumptionsSummary: "Review wildfire ignition pressure, fuel dryness, wind severity, suppression effectiveness, and exposed assets."
                ),
                impactDrivers: defaultImpactDrivers(),
                roadmapStages: defaultRoadmapStages(),
                thresholds: ThresholdEvaluationSummary(
                    status: .notEvaluated,
                    totalTargets: 0,
                    breachedCount: 0,
                    nearLimitCount: 0,
                    evaluations: [],
                    evaluatedAt: nil
                ),
                thresholdBreachActions: [],
                financialEffects: FinancialEffectsReview(
                    status: .notStarted,
                    planningImpactSummary: "",
                    financeReviewed: false,
                    magnitudeBand: nil,
                    methodologyNote: "",
                    currencyCode: "INR",
                    exposureValue: nil,
                    burnProbabilityProxy: bundle.totalBurntPercent.map { min(max($0 / 100.0, 0), 1) },
                    vulnerabilityRatio: nil,
                    deductiblePct: 0.05,
                    limitPct: 0.80,
                    estimatedGroundUpLoss: nil,
                    estimatedInsuredLoss: nil,
                    estimatedReinsuranceRecovery: nil
                ),
                provenance: ProvenanceSummary(
                    manifestURL: bundle.manifestURL,
                    reportURL: bundle.reportURL,
                    mappingURL: bundle.mappingURL,
                    simulatorLabel: bundle.simulatorLabel,
                    inputFolder: bundle.inputFolder,
                    outputDirectory: bundle.outputDirectory,
                    isComplete: FileManager.default.fileExists(atPath: bundle.manifestURL) &&
                        FileManager.default.fileExists(atPath: bundle.reportURL) &&
                        FileManager.default.fileExists(atPath: bundle.mappingURL),
                    artifactIndexURL: bundle.artifactIndexURL,
                    seed: nil,
                    binaryHash: nil
                ),
                conditions: [],
                reviewerNotes: ""
            )
        )
    }

    private func normalizedReviewRecord(_ record: TCFDReviewRecord) -> TCFDReviewRecord {
        var updated = record
        let now = Date()
        var severity: EscalationSeverity = .none

        if updated.approvalEvidence == nil {
            updated.approvalEvidence = transitionedApprovalEvidence(nil, for: updated.reviewStatus)
        }
        if updated.reviewEvents == nil {
            updated.reviewEvents = []
        }
        if updated.governance == nil {
            updated.governance = GovernanceAccountabilitySnapshot(
                boardCommittee: "Board / ESG Committee",
                boardOversightRequired: true,
                managementOwner: nil,
                riskOwner: nil,
                financeReviewer: nil,
                reviewCadence: "Quarterly or event-driven",
                delegatedAuthoritySummary: "",
                ermLinkageSummary: "Wildfire review should flow into the corporate ERM register and board reporting pack."
            )
        }
        if updated.scenario.shortHorizonLabel == nil {
            updated.scenario.shortHorizonLabel = "0-3 years"
        }
        if updated.scenario.mediumHorizonLabel == nil {
            updated.scenario.mediumHorizonLabel = "3-10 years"
        }
        if updated.scenario.longHorizonLabel == nil {
            updated.scenario.longHorizonLabel = "10+ years"
        }
        if updated.scenario.baselineScenarioName == nil || updated.scenario.baselineScenarioName?.isEmpty == true {
            updated.scenario.baselineScenarioName = updated.scenario.tcfdScenarioLabel
        }
        if updated.scenario.baselineRunID == nil || updated.scenario.baselineRunID?.isEmpty == true {
            updated.scenario.baselineRunID = updated.runID
        }
        if updated.scenario.wildfireAssumptionsSummary == nil {
            updated.scenario.wildfireAssumptionsSummary = "Review wildfire ignition pressure, fuel dryness, wind severity, suppression effectiveness, and exposed assets."
        }
        updated.scenario = refreshedScenarioComparison(for: updated)
        if updated.impactDrivers == nil || updated.impactDrivers?.isEmpty == true {
            updated.impactDrivers = defaultImpactDrivers()
        }
        if updated.roadmapStages == nil || updated.roadmapStages?.isEmpty == true {
            updated.roadmapStages = defaultRoadmapStages()
        }
        updated.financialEffects = refreshedFinancialEffects(for: updated)
        updated.thresholdBreachActions = syncedThresholdBreachActions(for: updated, existing: updated.thresholdBreachActions ?? [])
        let reviewIssues = readyForReviewIssues(for: updated)
        let boardIssues = readyForBoardIssues(for: updated)
        let overdue = updated.dueDate.map { $0 < now } ?? false
        let dueSoon = updated.dueDate.map { $0 >= now && $0 < Calendar.current.date(byAdding: .day, value: 3, to: now) ?? $0 } ?? false
        let breachedThresholds = updated.thresholds.status == .breached || updated.thresholds.breachedCount > 0
        let breachedWithResponse = breachedThresholds && hasDocumentedThresholdResponse(updated)
        let lateStage = updated.reviewStatus == .managementReview || updated.reviewStatus == .boardPackReady
        let packageClaimsBoardReady = updated.packageState == .readyForBoard

        if packageClaimsBoardReady && !boardIssues.isEmpty {
            severity = .critical
        } else if lateStage && !updated.provenance.isComplete {
            severity = .critical
        } else if lateStage && !updated.financialEffects.financeReviewed {
            severity = .critical
        } else if breachedThresholds && !breachedWithResponse {
            severity = .critical
        } else if overdue || breachedWithResponse || (lateStage && updated.financialEffects.status != .notStarted && !updated.financialEffects.financeReviewed) || updated.decision == .requestChanges {
            severity = .material
        } else if updated.thresholds.status == .nearLimit || dueSoon || !reviewIssues.isEmpty {
            severity = .warning
        }

        updated.packageState = recommendedPackageState(for: updated)
        updated.reviewStatus = normalizedReviewStatus(for: updated)
        updated.escalationSeverity = severity
        updated.roadmapStages = buildRoadmapStages(
            for: TCFDRunArtifactBundle(
                runID: updated.runID,
                bundleURL: "",
                manifestURL: updated.provenance.manifestURL,
                reportURL: updated.provenance.reportURL,
                summaryJSONURL: "",
                summaryCSVURL: "",
                artifactIndexURL: updated.provenance.artifactIndexURL ?? "",
                mappingURL: updated.provenance.mappingURL,
                rawStdoutURL: "",
                rawStderrURL: "",
                generatedAt: updated.preparedAt,
                timestamp: updated.preparedAt,
                simulatorCode: "",
                simulatorLabel: updated.provenance.simulatorLabel,
                inputFolder: updated.provenance.inputFolder,
                outputDirectory: updated.provenance.outputDirectory,
                totalBurnt: nil,
                totalCells: nil,
                totalBurntPercent: nil,
                highestROS: nil,
                lowestROS: nil,
                scenarioName: updated.scenario.scenarioName,
                tcfdScenarioLabel: updated.scenario.tcfdScenarioLabel,
                scenarioPathway: updated.scenario.comparatorScenarioName,
                scenarioHorizon: updated.scenario.shortHorizonLabel,
                governanceSummary: [],
                strategySummary: [],
                riskManagementSummary: [],
                metricsSummary: [],
                reviewRecordURL: "",
                reviewRecord: updated,
                loadedFromDisk: true
            ),
            record: updated,
            targetBands: updated.thresholds.evaluations.map {
                TargetBand(id: $0.targetBandID ?? UUID(), metricName: $0.metricName, thresholdValue: 0, unit: "", comparison: .lessThanOrEqual, notes: "")
            }
        )

        if updated.reviewStatus == .approved || updated.reviewStatus == .approvedWithConditions {
            updated.approvedAt = updated.approvedAt ?? now
        }
        if updated.reviewStatus == .approvedWithConditions {
            updated.conditions = mergedConditionsWithThresholdActions(record: updated)
        }
        return updated
    }

    private func transitionedApprovalEvidence(_ current: ApprovalEvidence?,
                                              for status: ReviewStatus) -> ApprovalEvidence {
        workflowPolicy.transitionedApprovalEvidence(current, for: status)
    }

    private func appendedReviewEvent(existing: [ReviewEvent]?,
                                     action: String,
                                     status: ReviewStatus,
                                     note: String?) -> [ReviewEvent] {
        workflowPolicy.appendedReviewEvent(existing: existing, action: action, status: status, note: note)
    }

    private func defaultImpactDrivers() -> [WildfireImpactDriverAssessment] {
        [
            WildfireImpactDriverAssessment(
                category: .physical,
                driverName: "Extreme fire weather",
                shortTermView: "Acute wildfire weather can disrupt near-term operations and drive immediate burn exposure.",
                mediumTermView: "More frequent severe fire weather increases adaptation and maintenance pressure.",
                longTermView: "Persistent warming increases chronic physical risk and asset relocation pressure.",
                ermLinked: true,
                responseSummary: "Track burn outcomes, weather stress, and site hardening priorities."
            ),
            WildfireImpactDriverAssessment(
                category: .transition,
                driverName: "Insurance and resilience costs",
                shortTermView: "Premium pressure and disclosure scrutiny can shift operating costs quickly.",
                mediumTermView: "Resilience capex and insurer requirements may reshape planning assumptions.",
                longTermView: "Cost of insurability and regulatory expectations can alter portfolio viability.",
                ermLinked: true,
                responseSummary: "Translate wildfire metrics into finance review, risk appetite, and capital planning."
            ),
            WildfireImpactDriverAssessment(
                category: .opportunity,
                driverName: "Adaptation and resilience opportunity",
                shortTermView: "Current studies can identify urgent hardening and screening actions.",
                mediumTermView: "Scenario comparisons can improve asset prioritisation and preparedness.",
                longTermView: "Wildfire analytics can support resilience strategy, insurance dialogue, and portfolio steering.",
                ermLinked: true,
                responseSummary: "Document adaptation actions and value of resilience interventions."
            )
        ]
    }

    private func defaultRoadmapStages() -> [RoadmapStageProgress] {
        [
            RoadmapStageProgress(
                key: .packageGenerated,
                title: "Package generated",
                detail: "Manifest, report, and mapping bundle created from a successful run.",
                isComplete: false
            ),
            RoadmapStageProgress(
                key: .thresholdsReviewed,
                title: "Thresholds reviewed",
                detail: "Target bands still need to be evaluated against the run package.",
                isComplete: false
            ),
            RoadmapStageProgress(
                key: .financeReviewed,
                title: "Finance reviewed",
                detail: "Financial-effects review still needs to be completed.",
                isComplete: false
            ),
            RoadmapStageProgress(
                key: .boardReady,
                title: "Board ready",
                detail: "Governance chain, provenance, thresholds, and finance review must be complete.",
                isComplete: false
            )
        ]
    }

    private func buildScenarioSnapshot(for bundle: TCFDRunArtifactBundle,
                                       scenario: ScenarioDefinition?,
                                       existing: ReviewScenarioSnapshot) -> ReviewScenarioSnapshot {
        var snapshot = existing
        snapshot.scenarioName = scenario?.name ?? snapshot.scenarioName
        snapshot.tcfdScenarioLabel = scenario?.tcfdScenarioLabel ?? snapshot.tcfdScenarioLabel
        snapshot.simulatorLabel = bundle.simulatorLabel
        if let horizon = scenario?.horizonLabel, !horizon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.shortHorizonLabel = horizon
        }
        if snapshot.baselineScenarioName == nil || snapshot.baselineScenarioName?.isEmpty == true {
            snapshot.baselineScenarioName = scenario?.name ?? bundle.simulatorLabel
        }
        if let pathway = scenario?.pathwayLabel, !pathway.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.comparatorScenarioName = pathway
        }
        if snapshot.baselineRunID == nil || snapshot.baselineRunID?.isEmpty == true {
            snapshot.baselineRunID = bundle.runID
        }
        if snapshot.wildfireAssumptionsSummary == nil || snapshot.wildfireAssumptionsSummary?.isEmpty == true {
            snapshot.wildfireAssumptionsSummary = "Review ignition pressure, burn probability, exposed assets, suppression posture, and operating disruption under the active wildfire scenario."
        }
        return refreshedScenarioComparison(snapshot: snapshot)
    }

    private struct ScenarioComparisonEvidence {
        let baselineBundle: TCFDRunArtifactBundle
        let comparatorBundle: TCFDRunArtifactBundle
        let baselineReview: TCFDReviewRecord
        let comparatorReview: TCFDReviewRecord
    }

    private struct ComparisonMetricRow {
        let metric: String
        let baseline: String
        let comparator: String
        let delta: String
        let interpretation: String
    }

    private func refreshedScenarioComparison(for record: TCFDReviewRecord) -> ReviewScenarioSnapshot {
        refreshedScenarioComparison(snapshot: record.scenario)
    }

    private func refreshedScenarioComparison(snapshot: ReviewScenarioSnapshot) -> ReviewScenarioSnapshot {
        var snapshot = snapshot
        guard let evidence = resolvedComparisonEvidence(baselineRunID: snapshot.baselineRunID,
                                                        comparatorRunID: snapshot.comparatorRunID) else {
            return snapshot
        }

        snapshot.baselineScenarioName = snapshot.baselineScenarioName ?? evidence.baselineBundle.scenarioName ?? evidence.baselineBundle.runID
        snapshot.comparatorScenarioName = snapshot.comparatorScenarioName ?? evidence.comparatorBundle.scenarioName ?? evidence.comparatorBundle.runID
        snapshot.shortTermDeltaSummary = shortTermComparisonSummary(evidence)
        snapshot.mediumTermDeltaSummary = mediumTermComparisonSummary(evidence)
        snapshot.longTermDeltaSummary = longTermComparisonSummary(evidence)
        snapshot.resilienceConclusion = resilienceConclusionSummary(evidence)
        return snapshot
    }

    private func buildGovernanceSnapshot(from governance: GovernanceMetadata,
                                         existing: GovernanceAccountabilitySnapshot?,
                                         record: TCFDReviewRecord) -> GovernanceAccountabilitySnapshot {
        var snapshot = existing ?? GovernanceAccountabilitySnapshot()
        let boardOwner = governance.boardOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let managementOwner = governance.managementOwner.trimmingCharacters(in: .whitespacesAndNewlines)

        snapshot.boardCommittee = boardOwner.isEmpty ? (snapshot.boardCommittee ?? "Board / ESG Committee") : boardOwner
        snapshot.boardOversightRequired = snapshot.boardOversightRequired ?? true
        snapshot.managementOwner = managementOwner.isEmpty ? snapshot.managementOwner : PersonRef(name: managementOwner, title: "Management Owner")
        snapshot.riskOwner = record.currentOwner ?? record.accountableExecutive ?? snapshot.riskOwner
        if record.financialEffects.financeReviewed, snapshot.financeReviewer == nil {
            snapshot.financeReviewer = PersonRef(name: "Finance Review", title: "Completed")
        }
        if snapshot.reviewCadence == nil || snapshot.reviewCadence?.isEmpty == true {
            snapshot.reviewCadence = "Quarterly or event-driven"
        }
        if !governance.delegatedAuthorityNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.delegatedAuthoritySummary = governance.delegatedAuthorityNotes
        }
        if !governance.riskAppetiteNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot.ermLinkageSummary = governance.riskAppetiteNotes
        } else if snapshot.ermLinkageSummary == nil || snapshot.ermLinkageSummary?.isEmpty == true {
            snapshot.ermLinkageSummary = "Wildfire review should flow into the corporate ERM register and board reporting pack."
        }
        return snapshot
    }

    private func shortTermComparisonSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        var fragments: [String] = []
        if let burnSummary = deltaSentence(metric: "Burnt %",
                                           baselineValue: evidence.baselineBundle.totalBurntPercent,
                                           comparatorValue: evidence.comparatorBundle.totalBurntPercent,
                                           lowerIsBetter: true,
                                           unitSuffix: "%") {
            fragments.append(burnSummary)
        }
        if let rosSummary = deltaSentence(metric: "Peak ROS",
                                          baselineValue: evidence.baselineBundle.highestROS,
                                          comparatorValue: evidence.comparatorBundle.highestROS,
                                          lowerIsBetter: true,
                                          unitSuffix: " m/min") {
            fragments.append(rosSummary)
        }
        return fragments.isEmpty
            ? "Short-term delta still needs comparable burn-percentage and ROS evidence."
            : fragments.joined(separator: " ")
    }

    private func mediumTermComparisonSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let breachDelta = evidence.comparatorReview.thresholds.breachedCount - evidence.baselineReview.thresholds.breachedCount
        let worsenedMetrics = thresholdTransitionMetrics(baseline: evidence.baselineReview,
                                                         comparator: evidence.comparatorReview,
                                                         worseningOnly: true)
        if let breachSummary = deltaSentence(metric: "Breached targets",
                                             baselineValue: Double(evidence.baselineReview.thresholds.breachedCount),
                                             comparatorValue: Double(evidence.comparatorReview.thresholds.breachedCount),
                                             lowerIsBetter: true,
                                             unitSuffix: "") {
            if !worsenedMetrics.isEmpty {
                return "\(breachSummary) Metrics under greater pressure: \(worsenedMetrics.joined(separator: ", "))."
            }
            if breachDelta == 0 {
                return "\(breachSummary) Target pressure is broadly stable across the paired packages."
            }
            return breachSummary
        }
        return "Medium-term delta still needs threshold-breach comparison evidence."
    }

    private func longTermComparisonSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let burnCellsSummary = deltaSentence(metric: "Burnt cells",
                                             baselineValue: evidence.baselineBundle.totalBurnt.map(Double.init),
                                             comparatorValue: evidence.comparatorBundle.totalBurnt.map(Double.init),
                                             lowerIsBetter: true,
                                             unitSuffix: "")
        let financeFocus = financeComparisonFocusSummary(evidence)
        if let burnCellsSummary {
            return "\(burnCellsSummary) \(financeFocus)"
        }
        return financeFocus
    }

    private func resilienceConclusionSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let materiality = comparisonMaterialitySummary(evidence)
        let financeFocus = financeComparisonFocusSummary(evidence)
        return "\(materiality) \(financeFocus)"
    }

    private func resolvedComparisonEvidence(baselineRunID: String?,
                                            comparatorRunID: String?,
                                            fallbackBundle: TCFDRunArtifactBundle? = nil,
                                            fallbackReview: TCFDReviewRecord? = nil) -> ScenarioComparisonEvidence? {
        let normalizedBaselineRunID = stringValue(baselineRunID)
        let normalizedComparatorRunID = stringValue(comparatorRunID)
        guard !normalizedBaselineRunID.isEmpty,
              !normalizedComparatorRunID.isEmpty,
              normalizedBaselineRunID != normalizedComparatorRunID else {
            return nil
        }

        guard let baselineBundle = bundle(for: normalizedBaselineRunID) ?? (fallbackBundle?.runID == normalizedBaselineRunID ? fallbackBundle : nil),
              let comparatorBundle = bundle(for: normalizedComparatorRunID) ?? (fallbackBundle?.runID == normalizedComparatorRunID ? fallbackBundle : nil) else {
            return nil
        }

        let baselineReview = baselineBundle.runID == fallbackReview?.runID
            ? fallbackReview!
            : (baselineBundle.reviewRecord ?? defaultReviewRecord(for: baselineBundle))
        let comparatorReview = comparatorBundle.runID == fallbackReview?.runID
            ? fallbackReview!
            : (comparatorBundle.reviewRecord ?? defaultReviewRecord(for: comparatorBundle))

        return ScenarioComparisonEvidence(
            baselineBundle: baselineBundle,
            comparatorBundle: comparatorBundle,
            baselineReview: baselineReview,
            comparatorReview: comparatorReview
        )
    }

    private func comparisonMaterialitySummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let burnDelta = (evidence.comparatorBundle.totalBurntPercent ?? 0) - (evidence.baselineBundle.totalBurntPercent ?? 0)
        let rosDelta = (evidence.comparatorBundle.highestROS ?? 0) - (evidence.baselineBundle.highestROS ?? 0)
        let breachDelta = evidence.comparatorReview.thresholds.breachedCount - evidence.baselineReview.thresholds.breachedCount

        var worseningDrivers: [String] = []
        var improvingDrivers: [String] = []

        if abs(burnDelta) >= 2.0 {
            if burnDelta > 0 {
                worseningDrivers.append("burn percentage")
            } else {
                improvingDrivers.append("burn percentage")
            }
        }
        let rosMaterialityThreshold = max(abs(evidence.baselineBundle.highestROS ?? 0) * 0.10, 0.5)
        if abs(rosDelta) >= rosMaterialityThreshold, evidence.baselineBundle.highestROS != nil, evidence.comparatorBundle.highestROS != nil {
            if rosDelta > 0 {
                worseningDrivers.append("peak rate of spread")
            } else {
                improvingDrivers.append("peak rate of spread")
            }
        }
        if breachDelta != 0 {
            if breachDelta > 0 {
                worseningDrivers.append("threshold breaches")
            } else {
                improvingDrivers.append("threshold breaches")
            }
        }

        if !worseningDrivers.isEmpty {
            return "Material change assessment: comparator scenario is materially worse than baseline, driven by \(worseningDrivers.joined(separator: ", "))."
        }
        if !improvingDrivers.isEmpty {
            return "Material change assessment: comparator scenario is materially better than baseline, driven by \(improvingDrivers.joined(separator: ", "))."
        }
        return "Material change assessment: comparator scenario does not materially change the wildfire profile relative to baseline."
    }

    private func financeComparisonFocusSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let burnDelta = (evidence.comparatorBundle.totalBurntPercent ?? 0) - (evidence.baselineBundle.totalBurntPercent ?? 0)
        let breachDelta = evidence.comparatorReview.thresholds.breachedCount - evidence.baselineReview.thresholds.breachedCount
        if burnDelta >= 2.0 || breachDelta > 0 {
            return "Finance focus should tighten around insurance pricing, resilience capex, and business interruption assumptions because the comparator package shows higher wildfire pressure."
        }
        if burnDelta <= -2.0 && breachDelta <= 0 {
            return "Finance focus can test whether the current magnitude band remains conservative, as the comparator package does not worsen wildfire pressure against baseline."
        }
        return "Finance focus remains centered on validating current insurance, resilience capex, and interruption assumptions because comparison evidence is broadly neutral."
    }

    private func thresholdTransitionMetrics(baseline: TCFDReviewRecord,
                                            comparator: TCFDReviewRecord,
                                            worseningOnly: Bool) -> [String] {
        let baselineMap = mergedThresholdStatusMap(baseline.thresholds.evaluations)
        let comparatorMap = mergedThresholdStatusMap(comparator.thresholds.evaluations)
        return comparatorMap.compactMap { metricName, comparatorStatus in
            guard let baselineStatus = baselineMap[metricName] else { return nil }
            let delta = thresholdStatusSeverity(comparatorStatus) - thresholdStatusSeverity(baselineStatus)
            if worseningOnly, delta > 0 {
                return metricName
            }
            if !worseningOnly, delta < 0 {
                return metricName
            }
            return nil
        }
        .sorted()
    }

    private func thresholdStatusSeverity(_ status: ThresholdEvaluationStatus) -> Int {
        switch status {
        case .notEvaluated: return 0
        case .withinTolerance: return 1
        case .nearLimit: return 2
        case .breached: return 3
        }
    }

    private func deltaSentence(metric: String,
                               baselineValue: Double?,
                               comparatorValue: Double?,
                               lowerIsBetter: Bool,
                               unitSuffix: String) -> String? {
        guard let baselineValue, let comparatorValue else { return nil }
        let delta = comparatorValue - baselineValue
        let direction: String
        if abs(delta) < 0.0001 {
            direction = "remains unchanged"
        } else if (delta < 0 && lowerIsBetter) || (delta > 0 && !lowerIsBetter) {
            direction = "improves"
        } else {
            direction = "deteriorates"
        }

        let formattedBaseline = formattedComparisonValue(baselineValue, unitSuffix: unitSuffix)
        let formattedComparator = formattedComparisonValue(comparatorValue, unitSuffix: unitSuffix)
        let formattedDelta = formattedComparisonDelta(delta, unitSuffix: unitSuffix)
        return "\(metric) shifts from \(formattedBaseline) to \(formattedComparator) (\(formattedDelta)); comparator \(direction) against baseline."
    }

    private func formattedComparisonValue(_ value: Double, unitSuffix: String) -> String {
        if unitSuffix == "%" {
            return String(format: "%.2f%%", value)
        }
        if value.rounded() == value {
            return "\(Int(value))\(unitSuffix)"
        }
        return String(format: "%.2f%@", value, unitSuffix)
    }

    private func formattedComparisonDelta(_ value: Double, unitSuffix: String) -> String {
        let prefix = value > 0 ? "+" : ""
        if unitSuffix == "%" {
            return String(format: "%@%.2f%%", prefix, value)
        }
        if value.rounded() == value {
            return "\(prefix)\(Int(value))\(unitSuffix)"
        }
        return String(format: "%@%.2f%@", prefix, value, unitSuffix)
    }

    private func evaluateThresholds(for bundle: TCFDRunArtifactBundle,
                                    targetBands: [TargetBand]) -> ThresholdEvaluationSummary {
        guard !targetBands.isEmpty else {
            return ThresholdEvaluationSummary(
                status: .notEvaluated,
                totalTargets: 0,
                breachedCount: 0,
                nearLimitCount: 0,
                evaluations: [],
                evaluatedAt: nil
            )
        }

        let evaluations = targetBands.map { evaluate(targetBand: $0, bundle: bundle) }
        let breachedCount = evaluations.filter { $0.status == .breached }.count
        let nearLimitCount = evaluations.filter { $0.status == .nearLimit }.count
        let overallStatus: ThresholdEvaluationStatus
        if breachedCount > 0 {
            overallStatus = .breached
        } else if nearLimitCount > 0 {
            overallStatus = .nearLimit
        } else if evaluations.contains(where: { $0.status == .withinTolerance }) {
            overallStatus = .withinTolerance
        } else {
            overallStatus = .notEvaluated
        }

        return ThresholdEvaluationSummary(
            status: overallStatus,
            totalTargets: targetBands.count,
            breachedCount: breachedCount,
            nearLimitCount: nearLimitCount,
            evaluations: evaluations,
            evaluatedAt: Date()
        )
    }

    private func evaluate(targetBand: TargetBand, bundle: TCFDRunArtifactBundle) -> ThresholdMetricEvaluation {
        let observation = observedMetric(for: targetBand.metricName, bundle: bundle)
        let status = evaluateObservedValue(observation.value,
                                           threshold: targetBand.thresholdValue,
                                           comparison: targetBand.comparison)
        return ThresholdMetricEvaluation(
            targetBandID: targetBand.id,
            metricName: targetBand.metricName,
            observedValue: observation.value,
            observedDisplayValue: observation.display,
            thresholdDisplayValue: "\(targetBand.comparison.displayName) \(formatThresholdValue(targetBand.thresholdValue)) \(targetBand.unit)".trimmingCharacters(in: .whitespaces),
            status: status
        )
    }

    private func observedMetric(for metricName: String,
                                bundle: TCFDRunArtifactBundle) -> (value: Double?, display: String) {
        let normalized = metricName.lowercased()
        if normalized.contains("burn probability") || normalized.contains("burn %") || normalized.contains("burnt percent") || normalized.contains("burn percent") {
            if let value = bundle.totalBurntPercent {
                return (value, String(format: "%.2f%%", value))
            }
            return (nil, "Unavailable")
        }
        if normalized.contains("burnt cells") || normalized.contains("burned cells") || normalized == "burnt" {
            if let value = bundle.totalBurnt {
                return (Double(value), "\(value)")
            }
            return (nil, "Unavailable")
        }
        if normalized.contains("total cells") {
            if let value = bundle.totalCells {
                return (Double(value), "\(value)")
            }
            return (nil, "Unavailable")
        }
        return (nil, "Unsupported metric")
    }

    private func evaluateObservedValue(_ observedValue: Double?,
                                       threshold: Double,
                                       comparison: TargetBand.Comparison) -> ThresholdEvaluationStatus {
        guard let observedValue else { return .notEvaluated }

        let breach: Bool
        let nearLimit: Bool
        let toleranceBand = max(abs(threshold) * 0.10, 0.01)

        switch comparison {
        case .lessThan:
            breach = observedValue >= threshold
            nearLimit = !breach && observedValue >= (threshold - toleranceBand)
        case .lessThanOrEqual:
            breach = observedValue > threshold
            nearLimit = !breach && observedValue >= (threshold - toleranceBand)
        case .greaterThan:
            breach = observedValue <= threshold
            nearLimit = !breach && observedValue <= (threshold + toleranceBand)
        case .greaterThanOrEqual:
            breach = observedValue < threshold
            nearLimit = !breach && observedValue <= (threshold + toleranceBand)
        }

        if breach {
            return .breached
        }
        if nearLimit {
            return .nearLimit
        }
        return .withinTolerance
    }

    private func buildImpactDrivers(for bundle: TCFDRunArtifactBundle,
                                    scenario: ScenarioDefinition?,
                                    thresholds: ThresholdEvaluationSummary,
                                    financialEffects: FinancialEffectsReview,
                                    existing: [WildfireImpactDriverAssessment]?) -> [WildfireImpactDriverAssessment] {
        let burnPercent = bundle.totalBurntPercent ?? 0
        let scenarioLabel = scenario?.tcfdScenarioLabel ?? bundle.simulatorLabel
        let thresholdMessage: String
        switch thresholds.status {
        case .breached:
            thresholdMessage = "Current target bands are breached."
        case .nearLimit:
            thresholdMessage = "Current target bands are near limit."
        case .withinTolerance:
            thresholdMessage = "Current target bands remain within tolerance."
        case .notEvaluated:
            thresholdMessage = "Target bands have not been evaluated yet."
        }

        let currentByName = mergedImpactDriverMap(existing ?? [])

        func mergedDriver(category: ImpactDriverCategory,
                          name: String,
                          short: String,
                          medium: String,
                          long: String,
                          response: String) -> WildfireImpactDriverAssessment {
            var driver = currentByName[name] ?? WildfireImpactDriverAssessment(
                category: category,
                driverName: name,
                shortTermView: short,
                mediumTermView: medium,
                longTermView: long,
                ermLinked: true,
                responseSummary: response
            )
            driver.category = category
            driver.shortTermView = short
            driver.mediumTermView = medium
            driver.longTermView = long
            if driver.responseSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                driver.responseSummary = response
            }
            return driver
        }

        return [
            mergedDriver(
                category: .physical,
                name: "Extreme fire weather",
                short: burnPercent > 15 ? "Recent runs under \(scenarioLabel) show elevated burn exposure and acute operational pressure." : "Recent runs under \(scenarioLabel) remain in a lower operational burn range.",
                medium: "Wildfire frequency and severity can increase adaptation, maintenance, and insurance pressure over the medium term.",
                long: "Persistent warming can raise chronic wildfire exposure and challenge long-term asset resilience.",
                response: thresholdMessage
            ),
            mergedDriver(
                category: .transition,
                name: "Insurance and resilience costs",
                short: financialEffects.status == .notStarted ? "Financial implications are not yet translated into planning terms." : "Financial effects are entering planning and review.",
                medium: "Insurer requirements and resilience capex can reshape mid-term planning assumptions.",
                long: "Long-term insurability and climate disclosure expectations can alter portfolio viability.",
                response: financialEffects.financeReviewed ? "Finance review has been completed." : "Finance review remains pending."
            ),
            mergedDriver(
                category: .opportunity,
                name: "Adaptation and resilience opportunity",
                short: "Current studies can guide near-term hardening and screening priorities.",
                medium: "Scenario comparisons can improve investment sequencing and preparedness planning.",
                long: "Wildfire intelligence can support portfolio resilience strategy and executive oversight.",
                response: "Use run packages to document the value of resilience interventions and adaptation actions."
            )
        ]
    }

    private func refreshedFinancialEffects(for record: TCFDReviewRecord) -> FinancialEffectsReview {
        var updated = record.financialEffects

        if stringValue(updated.currencyCode).isEmpty {
            updated.currencyCode = "INR"
        }

        if updated.burnProbabilityProxy == nil,
           let bundle = bundles.first(where: { $0.runID == record.runID }),
           let burntPercent = bundle.totalBurntPercent {
            updated.burnProbabilityProxy = min(max(burntPercent / 100.0, 0), 1)
        }

        let burnProbability = updated.burnProbabilityProxy
        let vulnerabilityRatio = updated.vulnerabilityRatio
        let deductiblePct = FinancialLossEngine.normalizePercentInput(updated.deductiblePct) ?? 0
        let limitPct = FinancialLossEngine.normalizePercentInput(updated.limitPct) ?? 1

        guard let exposureValue = updated.exposureValue,
              exposureValue > 0,
              let burnProbability,
              let vulnerabilityRatio else {
            updated.estimatedGroundUpLoss = nil
            updated.estimatedInsuredLoss = nil
            updated.estimatedReinsuranceRecovery = nil
            return updated
        }

        let loss = FinancialLossEngine.computeLoss(
            tiv: exposureValue,
            burnProbability: burnProbability,
            vulnerabilityRatio: vulnerabilityRatio,
            deductiblePct: deductiblePct,
            limitPct: limitPct
        )

        updated.deductiblePct = deductiblePct
        updated.limitPct = limitPct
        updated.estimatedGroundUpLoss = loss.gul
        updated.estimatedInsuredLoss = loss.il
        updated.estimatedReinsuranceRecovery = loss.ri

        if updated.status == .notStarted || updated.status == .qualitativeOnly {
            updated.status = .indicativeRange
        }
        if stringValue(updated.methodologyNote).isEmpty {
            updated.methodologyNote = "Indicative wildfire loss proxy based on exposure value, burn probability proxy, vulnerability ratio, deductible, and limit."
        }
        if stringValue(updated.magnitudeBand).isEmpty {
            updated.magnitudeBand = financialMagnitudeBand(for: loss.il, exposureValue: exposureValue)
        }

        return updated
    }

    private func financialMagnitudeBand(for loss: Double, exposureValue: Double) -> String {
        guard exposureValue > 0 else { return "Pending" }
        let ratio = loss / exposureValue
        switch ratio {
        case ..<0.05:
            return "Low"
        case ..<0.15:
            return "Moderate"
        case ..<0.30:
            return "Elevated"
        default:
            return "Material"
        }
    }

    private func buildRoadmapStages(for bundle: TCFDRunArtifactBundle,
                                    record: TCFDReviewRecord,
                                    targetBands: [TargetBand]) -> [RoadmapStageProgress] {
        let thresholdsComplete = !targetBands.isEmpty && record.thresholds.status != .notEvaluated
        let financeComplete = record.financialEffects.financeReviewed ||
            ((record.financialEffects.status == .indicativeRange || record.financialEffects.status == .quantified) &&
             record.financialEffects.estimatedGroundUpLoss != nil)
        let boardReady = readyForBoardIssues(for: record).isEmpty

        return [
            RoadmapStageProgress(
                key: .packageGenerated,
                title: "Package generated",
                detail: "Manifest, report, and mapping bundle created from the wildfire run \(bundle.runID).",
                isComplete: true
            ),
            RoadmapStageProgress(
                key: .thresholdsReviewed,
                title: "Thresholds reviewed",
                detail: thresholdsComplete ? "\(record.thresholds.totalTargets) target band(s) evaluated." : "Target bands still need to be evaluated against this package.",
                isComplete: thresholdsComplete
            ),
            RoadmapStageProgress(
                key: .financeReviewed,
                title: "Finance reviewed",
                detail: financeComplete ? "Financial-effects review is captured for this package." : "Financial-effects review still needs finance input.",
                isComplete: financeComplete
            ),
            RoadmapStageProgress(
                key: .boardReady,
                title: "Board ready",
                detail: boardReady ? "Governance chain, provenance, thresholds, and finance review are complete." : "Board-readiness is still blocked by incomplete workflow fields.",
                isComplete: boardReady
            )
        ]
    }

    private func recommendedPackageState(for record: TCFDReviewRecord) -> PackageLifecycleState {
        if readyForBoardIssues(for: record).isEmpty {
            return .readyForBoard
        }
        if readyForReviewIssues(for: record).isEmpty {
            return .readyForReview
        }

        let reviewRecordComplete = record.currentOwner?.isEmpty == false &&
            record.accountableExecutive?.isEmpty == false &&
            record.approver?.isEmpty == false
        let hasThresholds = record.thresholds.status != .notEvaluated
        let financeComplete = record.financialEffects.financeReviewed || record.financialEffects.status == .quantified

        if reviewRecordComplete {
            return .reviewRecordComplete
        }
        if record.provenance.isComplete {
            return .provenanceComplete
        }
        if financeComplete {
            return .financialsCaptured
        }
        if hasThresholds {
            return .thresholdsEvaluated
        }
        if !(record.scenario.tcfdScenarioLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return .scenarioLinked
        }
        return .generated
    }

    private func normalizedReviewStatus(for record: TCFDReviewRecord) -> ReviewStatus {
        let boardIssues = readyForBoardIssues(for: record)
        let reviewIssues = readyForReviewIssues(for: record)

        switch record.reviewStatus {
        case .approved, .approvedWithConditions, .rejected, .superseded, .changesRequested:
            return record.reviewStatus
        case .boardPackReady:
            return boardIssues.isEmpty ? .boardPackReady : .managementReview
        case .managementReview:
            return reviewIssues.isEmpty ? .managementReview : .packaged
        case .riskOwnerReview:
            return reviewIssues.isEmpty ? .riskOwnerReview : .packaged
        case .analystReview:
            return reviewIssues.isEmpty ? .analystReview : .packaged
        case .packaged:
            return .packaged
        }
    }

    private func hasDocumentedThresholdResponse(_ record: TCFDReviewRecord) -> Bool {
        workflowPolicy.hasDocumentedThresholdResponse(record)
    }

    private func requiresDocumentedResponseForThresholdBreach(_ record: TCFDReviewRecord) -> Bool {
        workflowPolicy.requiresDocumentedResponseForThresholdBreach(record)
    }

    private func breachedThresholdEvaluations(for record: TCFDReviewRecord) -> [ThresholdMetricEvaluation] {
        record.thresholds.evaluations.filter { $0.status == .breached }
    }

    private func syncedThresholdBreachActions(for record: TCFDReviewRecord,
                                              existing: [ThresholdBreachAction]) -> [ThresholdBreachAction] {
        workflowPolicy.syncedThresholdBreachActions(for: record, existing: existing)
    }

    private func thresholdBreachWorkflowIssues(for record: TCFDReviewRecord,
                                               requireRationale: Bool) -> [String] {
        workflowPolicy.thresholdBreachWorkflowIssues(for: record, requireRationale: requireRationale)
    }

    private func uniqueIssues(_ issues: [String]) -> [String] {
        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    private func mergedThresholdStatusMap(_ evaluations: [ThresholdMetricEvaluation]) -> [String: ThresholdEvaluationStatus] {
        evaluations.reduce(into: [String: ThresholdEvaluationStatus]()) { partial, evaluation in
            let key = evaluation.metricName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let nextSeverity = thresholdStatusSeverity(evaluation.status)
            if let current = partial[key], thresholdStatusSeverity(current) >= nextSeverity {
                return
            }
            partial[key] = evaluation.status
        }
    }

    private func mergedImpactDriverMap(_ drivers: [WildfireImpactDriverAssessment]) -> [String: WildfireImpactDriverAssessment] {
        drivers.reduce(into: [String: WildfireImpactDriverAssessment]()) { partial, driver in
            let key = driver.driverName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            guard let current = partial[key] else {
                partial[key] = driver
                return
            }

            var merged = current
            if merged.shortTermView.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.shortTermView = driver.shortTermView
            }
            if merged.mediumTermView.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.mediumTermView = driver.mediumTermView
            }
            if merged.longTermView.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.longTermView = driver.longTermView
            }
            if merged.responseSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.responseSummary = driver.responseSummary
            }
            merged.ermLinked = merged.ermLinked || driver.ermLinked
            partial[key] = merged
        }
    }

    private func mergedThresholdActionMap(_ actions: [ThresholdBreachAction]) -> [String: ThresholdBreachAction] {
        actions.reduce(into: [String: ThresholdBreachAction]()) { partial, action in
            let key = action.metricName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            guard let current = partial[key] else {
                partial[key] = action
                return
            }
            partial[key] = mergeThresholdAction(current, with: action)
        }
    }

    private func mergeThresholdAction(_ lhs: ThresholdBreachAction, with rhs: ThresholdBreachAction) -> ThresholdBreachAction {
        var merged = lhs
        if thresholdActionCompletenessScore(rhs) > thresholdActionCompletenessScore(lhs) {
            merged = rhs
        }

        if merged.breachSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.breachSummary = rhs.breachSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lhs.breachSummary : rhs.breachSummary
        }
        if merged.businessImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.businessImpactSummary = rhs.businessImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lhs.businessImpactSummary : rhs.businessImpactSummary
        }
        if merged.actionOwner?.isEmpty != false {
            merged.actionOwner = rhs.actionOwner?.isEmpty == false ? rhs.actionOwner : lhs.actionOwner
        }
        if merged.targetDate == nil {
            merged.targetDate = rhs.targetDate ?? lhs.targetDate
        }
        if merged.managementRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.managementRationale = rhs.managementRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lhs.managementRationale : rhs.managementRationale
        }
        merged.status = preferredMax(lhs.status, rhs.status, by: breachActionStatusRank)
        return merged
    }

    private func thresholdActionCompletenessScore(_ action: ThresholdBreachAction) -> Int {
        var score = 0
        if !action.breachSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if !action.businessImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if action.actionOwner?.isEmpty == false { score += 1 }
        if action.targetDate != nil { score += 1 }
        if !action.managementRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        score += breachActionStatusRank(action.status)
        return score
    }

    private func breachActionStatusRank(_ status: BreachActionStatus) -> Int {
        switch status {
        case .open: return 0
        case .inProgress: return 1
        case .closed: return 2
        }
    }

    private func preferredMax<T>(_ lhs: T, _ rhs: T, by rank: (T) -> Int) -> T {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private func reviewRecordNeedsRepair(_ record: TCFDReviewRecord) -> Bool {
        let thresholdActions = record.thresholdBreachActions ?? []
        let impactDrivers = record.impactDrivers ?? []
        let thresholdMetrics = record.thresholds.evaluations
        return hasDuplicateKeys(thresholdActions.map(\.metricName))
            || hasDuplicateKeys(impactDrivers.map(\.driverName))
            || hasDuplicateKeys(thresholdMetrics.map(\.metricName))
    }

    private func hasDuplicateKeys(_ keys: [String]) -> Bool {
        var seen = Set<String>()
        for key in keys.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            if !seen.insert(key).inserted {
                return true
            }
        }
        return false
    }

    private func activeThresholdBreachActions(for record: TCFDReviewRecord) -> [ThresholdBreachAction] {
        workflowPolicy.activeThresholdBreachActions(for: record)
    }

    private func mergedConditionsWithThresholdActions(record: TCFDReviewRecord) -> [String] {
        workflowPolicy.mergedConditionsWithThresholdActions(record: record)
    }

    private func stringValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func comparisonMetricRows(for evidence: ScenarioComparisonEvidence) -> [ComparisonMetricRow] {
        [
            comparisonMetricRow(metric: "Burnt cells",
                                baselineValue: evidence.baselineBundle.totalBurnt.map(Double.init),
                                comparatorValue: evidence.comparatorBundle.totalBurnt.map(Double.init),
                                lowerIsBetter: true,
                                unitSuffix: ""),
            comparisonMetricRow(metric: "Burnt %",
                                baselineValue: evidence.baselineBundle.totalBurntPercent,
                                comparatorValue: evidence.comparatorBundle.totalBurntPercent,
                                lowerIsBetter: true,
                                unitSuffix: "%"),
            comparisonMetricRow(metric: "Highest ROS",
                                baselineValue: evidence.baselineBundle.highestROS,
                                comparatorValue: evidence.comparatorBundle.highestROS,
                                lowerIsBetter: true,
                                unitSuffix: " m/min"),
            comparisonMetricRow(metric: "Breached targets",
                                baselineValue: Double(evidence.baselineReview.thresholds.breachedCount),
                                comparatorValue: Double(evidence.comparatorReview.thresholds.breachedCount),
                                lowerIsBetter: true,
                                unitSuffix: ""),
            comparisonMetricRow(metric: "Near-limit targets",
                                baselineValue: Double(evidence.baselineReview.thresholds.nearLimitCount),
                                comparatorValue: Double(evidence.comparatorReview.thresholds.nearLimitCount),
                                lowerIsBetter: true,
                                unitSuffix: "")
        ]
        .compactMap { $0 }
    }

    private func comparisonMetricRow(metric: String,
                                     baselineValue: Double?,
                                     comparatorValue: Double?,
                                     lowerIsBetter: Bool,
                                     unitSuffix: String) -> ComparisonMetricRow? {
        guard let baselineValue, let comparatorValue else { return nil }
        let delta = comparatorValue - baselineValue
        let interpretation: String
        if abs(delta) < 0.0001 {
            interpretation = "No material change"
        } else if (delta < 0 && lowerIsBetter) || (delta > 0 && !lowerIsBetter) {
            interpretation = "Comparator improves"
        } else {
            interpretation = "Comparator worsens"
        }

        return ComparisonMetricRow(
            metric: metric,
            baseline: formattedComparisonValue(baselineValue, unitSuffix: unitSuffix),
            comparator: formattedComparisonValue(comparatorValue, unitSuffix: unitSuffix),
            delta: formattedComparisonDelta(delta, unitSuffix: unitSuffix),
            interpretation: interpretation
        )
    }

    private func targetPressureShiftSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let worsenedMetrics = thresholdTransitionMetrics(baseline: evidence.baselineReview,
                                                         comparator: evidence.comparatorReview,
                                                         worseningOnly: true)
        let improvedMetrics = thresholdTransitionMetrics(baseline: evidence.baselineReview,
                                                         comparator: evidence.comparatorReview,
                                                         worseningOnly: false)
        if !worsenedMetrics.isEmpty {
            return "Comparator moves \(worsenedMetrics.count) metric(s) into a more severe threshold state: \(worsenedMetrics.joined(separator: ", "))."
        }
        if !improvedMetrics.isEmpty {
            return "Comparator relieves threshold pressure for \(improvedMetrics.joined(separator: ", "))."
        }
        return "Comparator does not change the severity state of the currently evaluated threshold metrics."
    }

    private func financeComparisonStatusSummary(_ evidence: ScenarioComparisonEvidence) -> String {
        let baselineStatus = evidence.baselineReview.financialEffects.status.displayName
        let comparatorStatus = evidence.comparatorReview.financialEffects.status.displayName
        if baselineStatus == comparatorStatus {
            return "Finance workflow maturity is aligned across baseline and comparator (\(baselineStatus)). \(financeComparisonFocusSummary(evidence))"
        }
        return "Finance workflow shifts from \(baselineStatus) in baseline to \(comparatorStatus) in comparator. \(financeComparisonFocusSummary(evidence))"
    }

    private func makeBoardPackReport(bundle: TCFDRunArtifactBundle,
                                     review: TCFDReviewRecord) -> String {
        let totalBurntText: String
        if let burnt = bundle.totalBurnt, let total = bundle.totalCells, total > 0 {
            let percent = bundle.totalBurntPercent.map { String(format: "%.2f%%", $0) } ?? "N/A"
            totalBurntText = "\(burnt) of \(total) cells burnt (\(percent))."
        } else {
            totalBurntText = "Aggregate burn outcome is unavailable."
        }
        let comparisonEvidence = resolvedComparisonEvidence(baselineRunID: review.scenario.baselineRunID,
                                                            comparatorRunID: review.scenario.comparatorRunID,
                                                            fallbackBundle: bundle,
                                                            fallbackReview: review)

        var lines: [String] = []
        lines.append("# Climate Liberator Approved Board Pack")
        lines.append("")
        lines.append("Run ID: `\(bundle.runID)`")
        lines.append("Review status: \(review.reviewStatus.displayName)")
        lines.append("Decision: \(review.decision.displayName)")
        if let approvedAt = review.approvedAt {
            lines.append("Approved at: \(approvedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        lines.append("")
        lines.append("## Governance")
        lines.append("")
        lines.append("- Prepared by: \(review.preparedBy.name) (\(review.preparedBy.title))")
        if let owner = review.currentOwner, !owner.isEmpty {
            lines.append("- Current owner: \(owner.name) (\(owner.title))")
        }
        if let executive = review.accountableExecutive, !executive.isEmpty {
            lines.append("- Accountable executive: \(executive.name) (\(executive.title))")
        }
        if let approver = review.approver, !approver.isEmpty {
            lines.append("- Approver: \(approver.name) (\(approver.title))")
        }
        if let committee = review.governance?.boardCommittee, !committee.isEmpty {
            lines.append("- Board committee: \(committee)")
        }
        if let authority = review.governance?.delegatedAuthoritySummary, !authority.isEmpty {
            lines.append("- Delegated authority: \(authority)")
        }
        lines.append("")
        lines.append("## Strategy")
        lines.append("")
        lines.append("- Scenario: \(review.scenario.scenarioName)")
        lines.append("- TCFD label: \(review.scenario.tcfdScenarioLabel)")
        if let baseline = review.scenario.baselineScenarioName, !baseline.isEmpty {
            lines.append("- Baseline scenario: \(baseline)")
        }
        if let baselineRunID = review.scenario.baselineRunID, !baselineRunID.isEmpty {
            lines.append("- Baseline run ID: \(baselineRunID)")
        }
        if let comparator = review.scenario.comparatorScenarioName, !comparator.isEmpty {
            lines.append("- Comparator / pathway: \(comparator)")
        }
        if let comparatorRunID = review.scenario.comparatorRunID, !comparatorRunID.isEmpty {
            lines.append("- Comparator run ID: \(comparatorRunID)")
        }
        lines.append("- Horizons: short \(review.scenario.shortHorizonLabel ?? "N/A"), medium \(review.scenario.mediumHorizonLabel ?? "N/A"), long \(review.scenario.longHorizonLabel ?? "N/A")")
        if let assumptions = review.scenario.wildfireAssumptionsSummary, !assumptions.isEmpty {
            lines.append("- Wildfire assumptions: \(assumptions)")
        }
        if let comparisonEvidence {
            lines.append("")
            lines.append("### Comparative Scenario Results")
            lines.append("- Short-term delta: \(review.scenario.shortTermDeltaSummary ?? shortTermComparisonSummary(comparisonEvidence))")
            lines.append("- Medium-term delta: \(review.scenario.mediumTermDeltaSummary ?? mediumTermComparisonSummary(comparisonEvidence))")
            lines.append("- Long-term delta: \(review.scenario.longTermDeltaSummary ?? longTermComparisonSummary(comparisonEvidence))")
            lines.append("- \(comparisonMaterialitySummary(comparisonEvidence))")
            lines.append("- Resilience conclusion: \(review.scenario.resilienceConclusion ?? resilienceConclusionSummary(comparisonEvidence))")
        } else {
            if let shortDelta = review.scenario.shortTermDeltaSummary, !shortDelta.isEmpty {
                lines.append("- Short-term delta: \(shortDelta)")
            }
            if let mediumDelta = review.scenario.mediumTermDeltaSummary, !mediumDelta.isEmpty {
                lines.append("- Medium-term delta: \(mediumDelta)")
            }
            if let longDelta = review.scenario.longTermDeltaSummary, !longDelta.isEmpty {
                lines.append("- Long-term delta: \(longDelta)")
            }
            if let resilienceConclusion = review.scenario.resilienceConclusion, !resilienceConclusion.isEmpty {
                lines.append("- Resilience conclusion: \(resilienceConclusion)")
            }
        }
        lines.append("")
        lines.append("## Risk Management")
        lines.append("")
        lines.append("- Package state: \(review.packageState.displayName)")
        lines.append("- Escalation: \(review.escalationSeverity.displayName)")
        lines.append("- Aggregate wildfire outcome: \(totalBurntText)")
        if !(review.impactDrivers ?? []).isEmpty {
            for driver in review.impactDrivers ?? [] {
                lines.append("- \(driver.category.displayName): \(driver.driverName) — \(driver.responseSummary)")
            }
        }
        if !(review.thresholdBreachActions ?? []).isEmpty {
            lines.append("")
            lines.append("### Threshold Breach Actions")
            for action in review.thresholdBreachActions ?? [] {
                let owner = action.actionOwner?.name.isEmpty == false ? action.actionOwner!.name : "Unassigned"
                let due = action.targetDate?.formatted(date: .abbreviated, time: .omitted) ?? "No due date"
                lines.append("- \(action.metricName): \(action.responseType.displayName) / \(action.status.displayName) / owner \(owner) / due \(due)")
                if !action.businessImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Impact: \(action.businessImpactSummary)")
                }
                if !action.managementRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Rationale: \(action.managementRationale)")
                }
            }
        }
        lines.append("")
        lines.append("## Metrics & Targets")
        lines.append("")
        lines.append("- Threshold status: \(review.thresholds.status.displayName)")
        lines.append("- Targets evaluated: \(review.thresholds.totalTargets)")
        lines.append("- Breaches: \(review.thresholds.breachedCount)")
        lines.append("- Near limit: \(review.thresholds.nearLimitCount)")
        if let evaluatedAt = review.thresholds.evaluatedAt {
            lines.append("- Thresholds evaluated at: \(evaluatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        for evaluation in review.thresholds.evaluations {
            lines.append("- \(evaluation.metricName): \(evaluation.observedDisplayValue) against \(evaluation.thresholdDisplayValue) (\(evaluation.status.displayName))")
        }
        if let comparisonEvidence {
            let metricRows = comparisonMetricRows(for: comparisonEvidence)
            if !metricRows.isEmpty {
                lines.append("")
                lines.append("### Baseline vs Comparator Metrics")
                lines.append("")
                lines.append("| Metric | Baseline | Comparator | Delta | Interpretation |")
                lines.append("| --- | ---: | ---: | ---: | --- |")
                for row in metricRows {
                    lines.append("| \(row.metric) | \(row.baseline) | \(row.comparator) | \(row.delta) | \(row.interpretation) |")
                }
            }
            lines.append("- Target pressure shift: \(targetPressureShiftSummary(comparisonEvidence))")
            lines.append("- Finance focus from comparison evidence: \(financeComparisonStatusSummary(comparisonEvidence))")
        }
        lines.append("- Financial effects: \(review.financialEffects.status.displayName)")
        lines.append("- Finance reviewed: \(review.financialEffects.financeReviewed ? "Yes" : "No")")
        if let exposureValue = review.financialEffects.exposureValue {
            let currency = review.financialEffects.currencyCode ?? "INR"
            lines.append("- Exposure basis: \(currency) \(formattedCurrency(exposureValue))")
        }
        if let burnProbability = review.financialEffects.burnProbabilityProxy {
            lines.append("- Burn probability proxy: \(formattedPercent(burnProbability))")
        }
        if let vulnerabilityRatio = review.financialEffects.vulnerabilityRatio {
            lines.append("- Vulnerability ratio: \(formattedPercent(vulnerabilityRatio))")
        }
        if let gul = review.financialEffects.estimatedGroundUpLoss {
            let currency = review.financialEffects.currencyCode ?? "INR"
            lines.append("- Estimated ground-up loss: \(currency) \(formattedCurrency(gul))")
        }
        if let il = review.financialEffects.estimatedInsuredLoss {
            let currency = review.financialEffects.currencyCode ?? "INR"
            lines.append("- Estimated insured loss: \(currency) \(formattedCurrency(il))")
        }
        if !review.financialEffects.planningImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- Planning impact summary: \(review.financialEffects.planningImpactSummary)")
        }
        if let methodology = review.financialEffects.methodologyNote, !methodology.isEmpty {
            lines.append("- Finance methodology: \(methodology)")
        }
        if let magnitude = review.financialEffects.magnitudeBand, !magnitude.isEmpty {
            lines.append("- Magnitude band: \(magnitude)")
        }
        if !review.conditions.isEmpty {
            lines.append("")
            lines.append("## Conditions")
            for condition in review.conditions {
                lines.append("- \(condition)")
            }
        }
        lines.append("")
        lines.append("## Provenance")
        lines.append("")
        lines.append("- Manifest: `\(review.provenance.manifestURL)`")
        lines.append("- Source report: `\(bundle.reportURL)`")
        lines.append("- Mapping: `\(review.provenance.mappingURL)`")
        lines.append("- Output directory: `\(review.provenance.outputDirectory)`")
        return lines.joined(separator: "\n") + "\n"
    }

    private func formatThresholdValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func candidateRoots() -> [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("ClimateLiberator"))
            roots.append(appSupport.appendingPathComponent("ClimateLiberator/TCFD"))
        }
        return roots
    }

    static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("ClimateLiberator/TCFD/review_index.json")
    }

    enum ExportError: LocalizedError {
        case missingBundle
        case notApproved

        var errorDescription: String? {
            switch self {
            case .missingBundle:
                return "The selected disclosure package could not be loaded."
            case .notApproved:
                return "Approve the package before exporting the final board pack."
            }
        }
    }

    private func formattedCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    private func formattedPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100.0)
    }
}
