import Foundation

struct ScenarioDefinition: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var notes: String
    var pathwayLabel: String? = nil
    var horizonLabel: String? = nil
    var simulatorCode: String
    var inputFolder: String
    var outputFolder: String
    var binaryPath: String
    var includeROS: Bool
    var weatherPeriodMinutes: Int
    var outputFormat: String
    var numberOfSimulations: Int
    var numberOfThreads: Int
    var seed: Int
    var tcfdScenarioLabel: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         name: String,
         notes: String,
         pathwayLabel: String? = nil,
         horizonLabel: String? = nil,
         simulatorCode: String,
         inputFolder: String,
         outputFolder: String,
         binaryPath: String,
         includeROS: Bool,
         weatherPeriodMinutes: Int,
         outputFormat: String,
         numberOfSimulations: Int,
         numberOfThreads: Int,
         seed: Int,
         tcfdScenarioLabel: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.notes = notes
        self.pathwayLabel = pathwayLabel
        self.horizonLabel = horizonLabel
        self.simulatorCode = simulatorCode
        self.inputFolder = inputFolder
        self.outputFolder = outputFolder
        self.binaryPath = binaryPath
        self.includeROS = includeROS
        self.weatherPeriodMinutes = weatherPeriodMinutes
        self.outputFormat = outputFormat
        self.numberOfSimulations = numberOfSimulations
        self.numberOfThreads = numberOfThreads
        self.seed = seed
        self.tcfdScenarioLabel = tcfdScenarioLabel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GovernanceMetadata: Codable, Hashable {
    var boardOwner: String
    var managementOwner: String
    var approvalStatus: String
    var reviewDate: Date?
    var riskAppetiteNotes: String
    var delegatedAuthorityNotes: String
}

struct TargetBand: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var metricName: String
    var thresholdValue: Double
    var unit: String
    var comparison: Comparison
    var notes: String

    enum Comparison: String, Codable, CaseIterable, Identifiable {
        case lessThan
        case lessThanOrEqual
        case greaterThan
        case greaterThanOrEqual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .lessThan: return "Less than"
            case .lessThanOrEqual: return "Less than or equal"
            case .greaterThan: return "Greater than"
            case .greaterThanOrEqual: return "Greater than or equal"
            }
        }
    }
}

struct ScenarioLibrarySnapshot: Codable {
    var scenarios: [ScenarioDefinition]
    var selectedScenarioID: UUID?
    var governanceMetadata: GovernanceMetadata
    var targetBands: [TargetBand]
    var updatedAt: Date
}

struct TCFDRunArtifactSummary: Identifiable, Codable, Hashable {
    var id: String
    var runID: String
    var bundleURL: String
    var manifestURL: String
    var reportURL: String
    var summaryJSONURL: String
    var summaryCSVURL: String
    var mappingURL: String
    var generatedAt: Date
    var timestamp: Date
    var simulatorLabel: String
    var inputFolder: String
    var outputDirectory: String
    var totalBurnt: Int?
    var totalCells: Int?
    var totalBurntPercent: Double?
    var highestROS: Double? = nil
    var lowestROS: Double? = nil
    var scenarioName: String? = nil
    var tcfdScenarioLabel: String? = nil
    var scenarioPathway: String? = nil
    var scenarioHorizon: String? = nil
    var governanceSummary: [String]
    var strategySummary: [String]
    var riskManagementSummary: [String]
    var metricsSummary: [String]
}

struct TCFDRunArtifactBundle: Identifiable, Codable, Hashable {
    var id: String { runID }
    var runID: String
    var bundleURL: String
    var manifestURL: String
    var reportURL: String
    var summaryJSONURL: String
    var summaryCSVURL: String
    var artifactIndexURL: String
    var mappingURL: String
    var rawStdoutURL: String
    var rawStderrURL: String
    var generatedAt: Date
    var timestamp: Date
    var simulatorCode: String
    var simulatorLabel: String
    var inputFolder: String
    var outputDirectory: String
    var totalBurnt: Int?
    var totalCells: Int?
    var totalBurntPercent: Double?
    var highestROS: Double? = nil
    var lowestROS: Double? = nil
    var scenarioName: String? = nil
    var tcfdScenarioLabel: String? = nil
    var scenarioPathway: String? = nil
    var scenarioHorizon: String? = nil
    var governanceSummary: [String]
    var strategySummary: [String]
    var riskManagementSummary: [String]
    var metricsSummary: [String]
    var reviewRecordURL: String
    var reviewRecord: TCFDReviewRecord?
    var loadedFromDisk: Bool
}

struct TCFDReviewBundleIndex: Codable {
    var bundles: [TCFDRunArtifactBundle]
    var updatedAt: Date
}

struct TCFDReviewRecord: Identifiable, Codable, Hashable {
    var id: String { runID }
    var runID: String
    var bundleID: String
    var reviewStatus: ReviewStatus
    var packageState: PackageLifecycleState
    var decision: ReviewDecision
    var escalationSeverity: EscalationSeverity
    var preparedBy: PersonRef
    var currentOwner: PersonRef?
    var accountableExecutive: PersonRef?
    var approver: PersonRef?
    var dueDate: Date?
    var preparedAt: Date
    var submittedAt: Date?
    var reviewedAt: Date?
    var approvedAt: Date?
    var updatedAt: Date
    var governance: GovernanceAccountabilitySnapshot? = nil
    var scenario: ReviewScenarioSnapshot
    var impactDrivers: [WildfireImpactDriverAssessment]? = nil
    var roadmapStages: [RoadmapStageProgress]? = nil
    var thresholds: ThresholdEvaluationSummary
    var thresholdBreachActions: [ThresholdBreachAction]? = nil
    var approvalEvidence: ApprovalEvidence? = nil
    var reviewEvents: [ReviewEvent]? = nil
    var financialEffects: FinancialEffectsReview
    var provenance: ProvenanceSummary
    var conditions: [String]
    var reviewerNotes: String
}

extension TCFDReviewRecord {
    static let placeholder = TCFDReviewRecord(
        runID: "placeholder",
        bundleID: "placeholder",
        reviewStatus: .packaged,
        packageState: .generated,
        decision: .none,
        escalationSeverity: .none,
        preparedBy: PersonRef(name: "", title: ""),
        currentOwner: nil,
        accountableExecutive: nil,
        approver: nil,
        dueDate: nil,
        preparedAt: Date(),
        submittedAt: nil,
        reviewedAt: nil,
        approvedAt: nil,
        updatedAt: Date(),
        scenario: ReviewScenarioSnapshot(scenarioName: "", tcfdScenarioLabel: "", simulatorLabel: ""),
        thresholds: ThresholdEvaluationSummary(status: .notEvaluated, totalTargets: 0, breachedCount: 0, nearLimitCount: 0),
        thresholdBreachActions: [],
        approvalEvidence: nil,
        reviewEvents: [],
        financialEffects: FinancialEffectsReview(status: .notStarted, planningImpactSummary: "", financeReviewed: false),
        provenance: ProvenanceSummary(manifestURL: "", reportURL: "", mappingURL: "", simulatorLabel: "", inputFolder: "", outputDirectory: "", isComplete: false),
        conditions: [],
        reviewerNotes: ""
    )
}

struct PersonRef: Codable, Hashable {
    var name: String
    var title: String
    var email: String? = nil

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GovernanceAccountabilitySnapshot: Codable, Hashable {
    var boardCommittee: String? = nil
    var boardOversightRequired: Bool? = nil
    var managementOwner: PersonRef? = nil
    var riskOwner: PersonRef? = nil
    var financeReviewer: PersonRef? = nil
    var reviewCadence: String? = nil
    var delegatedAuthoritySummary: String? = nil
    var ermLinkageSummary: String? = nil
}

struct ReviewScenarioSnapshot: Codable, Hashable {
    var scenarioName: String
    var tcfdScenarioLabel: String
    var simulatorLabel: String
    var shortHorizonLabel: String? = nil
    var mediumHorizonLabel: String? = nil
    var longHorizonLabel: String? = nil
    var baselineScenarioName: String? = nil
    var comparatorScenarioName: String? = nil
    var baselineRunID: String? = nil
    var comparatorRunID: String? = nil
    var shortTermDeltaSummary: String? = nil
    var mediumTermDeltaSummary: String? = nil
    var longTermDeltaSummary: String? = nil
    var resilienceConclusion: String? = nil
    var wildfireAssumptionsSummary: String? = nil
}

struct WildfireImpactDriverAssessment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var category: ImpactDriverCategory
    var driverName: String
    var shortTermView: String
    var mediumTermView: String
    var longTermView: String
    var ermLinked: Bool = false
    var responseSummary: String = ""
}

enum ImpactDriverCategory: String, Codable, CaseIterable, Identifiable {
    case physical
    case transition
    case opportunity

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

struct ThresholdEvaluationSummary: Codable, Hashable {
    var status: ThresholdEvaluationStatus
    var totalTargets: Int
    var breachedCount: Int
    var nearLimitCount: Int
    var evaluations: [ThresholdMetricEvaluation] = []
    var evaluatedAt: Date? = nil
}

struct ThresholdMetricEvaluation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var targetBandID: UUID?
    var metricName: String
    var observedValue: Double?
    var observedDisplayValue: String
    var thresholdDisplayValue: String
    var status: ThresholdEvaluationStatus
}

struct ThresholdBreachAction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var metricName: String
    var breachSummary: String
    var businessImpactSummary: String
    var responseType: BreachResponseType
    var actionOwner: PersonRef?
    var targetDate: Date?
    var status: BreachActionStatus
    var managementRationale: String
}

struct ApprovalEvidence: Codable, Hashable {
    var analystReviewed: Bool = false
    var riskOwnerReviewed: Bool = false
    var managementReviewed: Bool = false
    var approverConfirmed: Bool = false
    var evidenceNote: String = ""
}

struct ReviewEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var actor: String
    var action: String
    var reviewStatus: ReviewStatus
    var note: String? = nil
}

enum BreachResponseType: String, Codable, CaseIterable, Identifiable {
    case mitigate
    case accept
    case transfer
    case rerun
    case escalate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mitigate: return "Mitigate"
        case .accept: return "Accept"
        case .transfer: return "Transfer"
        case .rerun: return "Re-run"
        case .escalate: return "Escalate"
        }
    }
}

enum BreachActionStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case inProgress
    case closed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .closed: return "Closed"
        }
    }
}

struct RoadmapStageProgress: Identifiable, Codable, Hashable {
    var id: RoadmapStageKey { key }
    var key: RoadmapStageKey
    var title: String
    var detail: String
    var isComplete: Bool
}

enum RoadmapStageKey: String, Codable, CaseIterable, Identifiable {
    case packageGenerated
    case thresholdsReviewed
    case financeReviewed
    case boardReady

    var id: String { rawValue }
}

struct FinancialEffectsReview: Codable, Hashable {
    var status: FinancialEffectsStatus
    var planningImpactSummary: String
    var financeReviewed: Bool
    var magnitudeBand: String? = nil
    var methodologyNote: String? = nil
    var currencyCode: String? = nil
    var exposureValue: Double? = nil
    var burnProbabilityProxy: Double? = nil
    var vulnerabilityRatio: Double? = nil
    var deductiblePct: Double? = nil
    var limitPct: Double? = nil
    var estimatedGroundUpLoss: Double? = nil
    var estimatedInsuredLoss: Double? = nil
    var estimatedReinsuranceRecovery: Double? = nil
}

struct ProvenanceSummary: Codable, Hashable {
    var manifestURL: String
    var reportURL: String
    var mappingURL: String
    var simulatorLabel: String
    var inputFolder: String
    var outputDirectory: String
    var isComplete: Bool
    var artifactIndexURL: String? = nil
    var seed: Int? = nil
    var binaryHash: String? = nil
}

enum ReviewStatus: String, Codable, CaseIterable, Identifiable {
    case packaged
    case analystReview
    case riskOwnerReview
    case managementReview
    case boardPackReady
    case approved
    case approvedWithConditions
    case changesRequested
    case rejected
    case superseded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .packaged: return "Packaged"
        case .analystReview: return "Analyst Review"
        case .riskOwnerReview: return "Risk Owner Review"
        case .managementReview: return "Management Review"
        case .boardPackReady: return "Board Pack Ready"
        case .approved: return "Approved"
        case .approvedWithConditions: return "Approved With Conditions"
        case .changesRequested: return "Changes Requested"
        case .rejected: return "Rejected"
        case .superseded: return "Superseded"
        }
    }
}

enum PackageLifecycleState: String, Codable, CaseIterable, Identifiable {
    case generated
    case scenarioLinked
    case thresholdsEvaluated
    case financialsCaptured
    case provenanceComplete
    case reviewRecordComplete
    case readyForReview
    case readyForBoard
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .generated: return "Generated"
        case .scenarioLinked: return "Scenario Linked"
        case .thresholdsEvaluated: return "Thresholds Evaluated"
        case .financialsCaptured: return "Financials Captured"
        case .provenanceComplete: return "Provenance Complete"
        case .reviewRecordComplete: return "Review Record Complete"
        case .readyForReview: return "Ready For Review"
        case .readyForBoard: return "Ready For Board"
        case .archived: return "Archived"
        }
    }
}

enum ReviewDecision: String, Codable, CaseIterable, Identifiable {
    case none
    case approve
    case approveWithConditions
    case requestChanges
    case reject

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Decision"
        case .approve: return "Approve"
        case .approveWithConditions: return "Approve With Conditions"
        case .requestChanges: return "Request Changes"
        case .reject: return "Reject"
        }
    }
}

enum EscalationSeverity: String, Codable, CaseIterable, Identifiable {
    case none
    case warning
    case material
    case critical

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum FinancialEffectsStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case qualitativeOnly
    case indicativeRange
    case quantified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .qualitativeOnly: return "Qualitative Only"
        case .indicativeRange: return "Indicative Range"
        case .quantified: return "Quantified"
        }
    }
}

enum ThresholdEvaluationStatus: String, Codable, CaseIterable, Identifiable {
    case notEvaluated
    case withinTolerance
    case nearLimit
    case breached

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notEvaluated: return "Not Evaluated"
        case .withinTolerance: return "Within Tolerance"
        case .nearLimit: return "Near Limit"
        case .breached: return "Breached"
        }
    }
}
