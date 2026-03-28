import Foundation

protocol TCFDReviewWorkflowPolicying {
    func readyForReviewIssues(for record: TCFDReviewRecord) -> [String]
    func readyForBoardIssues(for record: TCFDReviewRecord, comparisonIssues: [String]) -> [String]
    func approvalIssues(for record: TCFDReviewRecord,
                        readyForBoardIssues: [String],
                        requireFinalTimestamps: Bool) -> [String]
    func historyIntegrityIssues(for record: TCFDReviewRecord) -> [String]
    func transitionedApprovalEvidence(_ current: ApprovalEvidence?, for status: ReviewStatus) -> ApprovalEvidence
    func appendedReviewEvent(existing: [ReviewEvent]?,
                             action: String,
                             status: ReviewStatus,
                             note: String?) -> [ReviewEvent]
    func syncedThresholdBreachActions(for record: TCFDReviewRecord,
                                      existing: [ThresholdBreachAction]) -> [ThresholdBreachAction]
    func thresholdBreachWorkflowIssues(for record: TCFDReviewRecord, requireRationale: Bool) -> [String]
    func hasDocumentedThresholdResponse(_ record: TCFDReviewRecord) -> Bool
    func requiresDocumentedResponseForThresholdBreach(_ record: TCFDReviewRecord) -> Bool
    func activeThresholdBreachActions(for record: TCFDReviewRecord) -> [ThresholdBreachAction]
    func mergedConditionsWithThresholdActions(record: TCFDReviewRecord) -> [String]
}

struct TCFDReviewWorkflowPolicy: TCFDReviewWorkflowPolicying {
    func readyForReviewIssues(for record: TCFDReviewRecord) -> [String] {
        var issues: [String] = []

        if record.preparedBy.isEmpty {
            issues.append("Prepared-by owner is missing.")
        }
        if !record.provenance.isComplete {
            issues.append("Disclosure provenance is incomplete.")
        }
        if normalized(record.provenance.manifestURL).isEmpty {
            issues.append("Manifest path is missing.")
        }
        if normalized(record.provenance.reportURL).isEmpty {
            issues.append("Report path is missing.")
        }
        if normalized(record.provenance.mappingURL).isEmpty {
            issues.append("TCFD mapping path is missing.")
        }
        if normalized(record.scenario.scenarioName).isEmpty {
            issues.append("Scenario name is missing.")
        }
        if normalized(record.scenario.tcfdScenarioLabel).isEmpty {
            issues.append("TCFD scenario label is missing.")
        }
        if normalized(record.scenario.shortHorizonLabel).isEmpty {
            issues.append("Short-term horizon label is missing.")
        }
        if normalized(record.scenario.mediumHorizonLabel).isEmpty {
            issues.append("Medium-term horizon label is missing.")
        }
        if normalized(record.scenario.longHorizonLabel).isEmpty {
            issues.append("Long-term horizon label is missing.")
        }
        if normalized(record.scenario.wildfireAssumptionsSummary).isEmpty {
            issues.append("Wildfire assumptions summary is missing.")
        }
        if (record.impactDrivers ?? []).isEmpty {
            issues.append("At least one wildfire impact driver assessment is required.")
        }
        if record.dueDate == nil {
            issues.append("Review due date is missing.")
        }
        issues.append(contentsOf: thresholdBreachWorkflowIssues(for: record, requireRationale: false))
        return uniqueIssues(issues)
    }

    func readyForBoardIssues(for record: TCFDReviewRecord, comparisonIssues: [String]) -> [String] {
        var issues = readyForReviewIssues(for: record)
        let governance = record.governance

        if record.currentOwner?.isEmpty != false {
            issues.append("Current review owner is missing.")
        }
        if record.accountableExecutive?.isEmpty != false {
            issues.append("Accountable executive is missing.")
        }
        if governance?.managementOwner?.isEmpty != false {
            issues.append("Management owner is missing from governance accountability.")
        }
        if governance?.riskOwner?.isEmpty != false {
            issues.append("Risk owner is missing from governance accountability.")
        }
        if normalized(governance?.boardCommittee).isEmpty {
            issues.append("Board committee is missing from governance accountability.")
        }
        if governance?.boardOversightRequired != true {
            issues.append("Board oversight requirement is not marked complete.")
        }
        if normalized(governance?.reviewCadence).isEmpty {
            issues.append("Review cadence is missing.")
        }
        if normalized(governance?.delegatedAuthoritySummary).isEmpty {
            issues.append("Delegated authority summary is missing.")
        }
        if normalized(governance?.ermLinkageSummary).isEmpty {
            issues.append("ERM linkage summary is missing.")
        }
        issues.append(contentsOf: comparisonIssues)

        let driverCategories = Set((record.impactDrivers ?? []).map(\.category))
        if !driverCategories.contains(.physical) {
            issues.append("A physical wildfire impact driver is required.")
        }
        if !driverCategories.contains(.transition) {
            issues.append("A transition impact driver is required.")
        }
        if !driverCategories.contains(.opportunity) {
            issues.append("An opportunity impact driver is required.")
        }

        if record.thresholds.status == .notEvaluated {
            issues.append("Thresholds are not evaluated.")
        }
        if record.thresholds.totalTargets <= 0 {
            issues.append("At least one target band must be configured before board readiness.")
        }
        if record.thresholds.evaluatedAt == nil {
            issues.append("Threshold evaluation timestamp is missing.")
        }
        if record.thresholds.totalTargets > 0 && record.thresholds.evaluations.isEmpty {
            issues.append("Threshold evaluation details are missing.")
        }

        if record.financialEffects.status == .notStarted {
            issues.append("Financial effects review has not started.")
        }
        if !record.financialEffects.financeReviewed {
            issues.append("Finance review is not complete.")
        }
        if record.financialEffects.planningImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Financial planning impact summary is missing.")
        }
        if normalized(record.financialEffects.methodologyNote).isEmpty {
            issues.append("Financial methodology note is missing.")
        }
        if (record.financialEffects.status == .indicativeRange || record.financialEffects.status == .quantified)
            && normalized(record.financialEffects.magnitudeBand).isEmpty {
            issues.append("Financial magnitude band is missing.")
        }
        if (record.financialEffects.status == .indicativeRange || record.financialEffects.status == .quantified)
            && record.financialEffects.exposureValue == nil {
            issues.append("Financial exposure value is missing.")
        }
        if record.financialEffects.status == .quantified
            && (record.financialEffects.estimatedGroundUpLoss == nil || record.financialEffects.estimatedInsuredLoss == nil) {
            issues.append("Quantified financial loss outputs are missing.")
        }

        if requiresDocumentedResponseForThresholdBreach(record) && !hasDocumentedThresholdResponse(record) {
            issues.append("Threshold breaches require a documented management response.")
        }
        issues.append(contentsOf: thresholdBreachWorkflowIssues(for: record, requireRationale: true))
        issues.append(contentsOf: historyIntegrityIssues(for: record))
        return uniqueIssues(issues)
    }

    func approvalIssues(for record: TCFDReviewRecord,
                        readyForBoardIssues: [String],
                        requireFinalTimestamps: Bool = true) -> [String] {
        var issues: [String] = []

        if !readyForBoardIssues.isEmpty {
            issues.append("Board-readiness issues must be resolved before approval evidence is complete.")
        }
        if record.reviewStatus != .boardPackReady &&
            record.reviewStatus != .approved &&
            record.reviewStatus != .approvedWithConditions {
            issues.append("Package must reach Board Pack Ready before approval can be recorded.")
        }
        if record.approver?.isEmpty != false {
            issues.append("Approver is missing.")
        }
        if record.reviewerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Reviewer notes are required before approval.")
        }
        if record.reviewedAt == nil {
            issues.append("Reviewed-at timestamp is missing.")
        }
        if record.approvalEvidence?.approverConfirmed != true {
            issues.append("Approval evidence is incomplete.")
        }
        if record.approvalEvidence?.evidenceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("Approval evidence note is missing.")
        }
        if requireFinalTimestamps && record.approvedAt == nil {
            issues.append("Approved-at timestamp is missing.")
        }
        if record.decision == .approveWithConditions && record.conditions.isEmpty {
            issues.append("Approval with conditions requires at least one recorded condition.")
        }
        if record.decision == .approveWithConditions && activeThresholdBreachActions(for: record).isEmpty {
            issues.append("Approval with conditions should retain at least one open threshold-breach action.")
        }

        issues.append(contentsOf: historyIntegrityIssues(for: record))
        return uniqueIssues(issues)
    }

    func historyIntegrityIssues(for record: TCFDReviewRecord) -> [String] {
        var issues: [String] = []
        let events = record.reviewEvents ?? []

        if record.reviewStatus != .packaged && record.submittedAt == nil {
            issues.append("Submitted-at timestamp is missing for the current workflow stage.")
        }
        if record.reviewStatus != .packaged && events.isEmpty {
            issues.append("Review event history is missing for the current workflow stage.")
        }
        if (record.reviewStatus == .riskOwnerReview ||
            record.reviewStatus == .managementReview ||
            record.reviewStatus == .boardPackReady ||
            record.reviewStatus == .approved ||
            record.reviewStatus == .approvedWithConditions ||
            record.reviewStatus == .changesRequested ||
            record.reviewStatus == .rejected) && record.reviewedAt == nil {
            issues.append("Reviewed-at timestamp is missing for the current workflow stage.")
        }
        if record.approvedAt != nil &&
            record.reviewStatus != .approved &&
            record.reviewStatus != .approvedWithConditions {
            issues.append("Approved-at timestamp is present even though the package is not in an approved state.")
        }
        if let submittedAt = record.submittedAt, submittedAt < record.preparedAt {
            issues.append("Submitted-at timestamp cannot be earlier than prepared-at.")
        }
        if let reviewedAt = record.reviewedAt, let submittedAt = record.submittedAt, reviewedAt < submittedAt {
            issues.append("Reviewed-at timestamp cannot be earlier than submitted-at.")
        }
        if let approvedAt = record.approvedAt {
            if let reviewedAt = record.reviewedAt, approvedAt < reviewedAt {
                issues.append("Approved-at timestamp cannot be earlier than reviewed-at.")
            }
            if approvedAt < record.preparedAt {
                issues.append("Approved-at timestamp cannot be earlier than prepared-at.")
            }
        }
        if (record.reviewStatus == .approved || record.reviewStatus == .approvedWithConditions) &&
            !events.contains(where: { $0.reviewStatus == .approved || $0.reviewStatus == .approvedWithConditions }) {
            issues.append("Approved packages must retain an approval event in history.")
        }

        return uniqueIssues(issues)
    }

    func transitionedApprovalEvidence(_ current: ApprovalEvidence?, for status: ReviewStatus) -> ApprovalEvidence {
        var evidence = current ?? ApprovalEvidence()

        switch status {
        case .packaged, .analystReview:
            break
        case .riskOwnerReview:
            evidence.analystReviewed = true
        case .managementReview:
            evidence.analystReviewed = true
            evidence.riskOwnerReviewed = true
        case .boardPackReady:
            evidence.analystReviewed = true
            evidence.riskOwnerReviewed = true
            evidence.managementReviewed = true
        case .approved, .approvedWithConditions:
            evidence.analystReviewed = true
            evidence.riskOwnerReviewed = true
            evidence.managementReviewed = true
            evidence.approverConfirmed = true
            if evidence.evidenceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                evidence.evidenceNote = "Approval workflow completed through Climate Liberator."
            }
        case .changesRequested, .rejected, .superseded:
            break
        }

        return evidence
    }

    func appendedReviewEvent(existing: [ReviewEvent]?,
                             action: String,
                             status: ReviewStatus,
                             note: String?) -> [ReviewEvent] {
        var events = existing ?? []
        let trimmedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = events.last,
           last.reviewStatus == status,
           last.action == trimmedAction,
           (last.note ?? "") == (trimmedNote ?? "") {
            return events
        }

        events.append(
            ReviewEvent(
                actor: "Climate Liberator",
                action: trimmedAction,
                reviewStatus: status,
                note: trimmedNote?.isEmpty == true ? nil : trimmedNote
            )
        )
        return events
    }

    func syncedThresholdBreachActions(for record: TCFDReviewRecord,
                                      existing: [ThresholdBreachAction]) -> [ThresholdBreachAction] {
        let breachedEvaluations = breachedThresholdEvaluations(for: record)
        guard !breachedEvaluations.isEmpty else { return [] }

        let existingByMetric = mergedThresholdActionMap(existing)
        return breachedEvaluations.map { evaluation in
            if var action = existingByMetric[evaluation.metricName] {
                if action.breachSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    action.breachSummary = "\(evaluation.metricName) exceeded \(evaluation.thresholdDisplayValue) with \(evaluation.observedDisplayValue)."
                }
                return action
            }
            return ThresholdBreachAction(
                metricName: evaluation.metricName,
                breachSummary: "\(evaluation.metricName) exceeded \(evaluation.thresholdDisplayValue) with \(evaluation.observedDisplayValue).",
                businessImpactSummary: "",
                responseType: .mitigate,
                actionOwner: nil,
                targetDate: nil,
                status: .open,
                managementRationale: ""
            )
        }
    }

    func hasDocumentedThresholdResponse(_ record: TCFDReviewRecord) -> Bool {
        if !thresholdBreachWorkflowIssues(for: record, requireRationale: true).isEmpty {
            return false
        }
        if !(record.thresholdBreachActions ?? []).isEmpty {
            return true
        }
        if !record.reviewerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return record.conditions.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func requiresDocumentedResponseForThresholdBreach(_ record: TCFDReviewRecord) -> Bool {
        record.thresholds.status == .breached || record.thresholds.breachedCount > 0
    }

    func activeThresholdBreachActions(for record: TCFDReviewRecord) -> [ThresholdBreachAction] {
        (record.thresholdBreachActions ?? []).filter { $0.status != .closed }
    }

    func mergedConditionsWithThresholdActions(record: TCFDReviewRecord) -> [String] {
        let actionConditions = activeThresholdBreachActions(for: record).map { action in
            let owner = action.actionOwner?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let ownerText = (owner?.isEmpty == false) ? owner! : "Unassigned owner"
            let dueText: String
            if let date = action.targetDate {
                dueText = date.formatted(date: .abbreviated, time: .omitted)
            } else {
                dueText = "No due date"
            }
            return "\(action.metricName): \(action.responseType.displayName) by \(ownerText) (\(dueText))."
        }
        return Array(NSOrderedSet(array: record.conditions + actionConditions)) as? [String] ?? (record.conditions + actionConditions)
    }

    func thresholdBreachWorkflowIssues(for record: TCFDReviewRecord,
                                       requireRationale: Bool) -> [String] {
        let breachedEvaluations = breachedThresholdEvaluations(for: record)
        guard !breachedEvaluations.isEmpty else { return [] }

        let actions = mergedThresholdActionMap(record.thresholdBreachActions ?? [])
        var issues: [String] = []

        for evaluation in breachedEvaluations {
            guard let action = actions[evaluation.metricName] else {
                issues.append("Add a threshold-breach action for \(evaluation.metricName).")
                continue
            }
            if action.actionOwner?.isEmpty != false {
                issues.append("Assign an owner for the \(evaluation.metricName) breach action.")
            }
            if action.targetDate == nil {
                issues.append("Set a target date for the \(evaluation.metricName) breach action.")
            }
            if action.businessImpactSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Summarize business impact for the \(evaluation.metricName) breach action.")
            }
            if requireRationale && action.managementRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Add management rationale for the \(evaluation.metricName) breach action.")
            }
        }
        return uniqueIssues(issues)
    }

    private func breachedThresholdEvaluations(for record: TCFDReviewRecord) -> [ThresholdMetricEvaluation] {
        record.thresholds.evaluations.filter { $0.status == .breached }
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

    private func uniqueIssues(_ issues: [String]) -> [String] {
        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
