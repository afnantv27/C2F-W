import Foundation

protocol TCFDReviewDiscoveryServicing {
    func discoverBundles(
        in roots: [URL],
        cache: TCFDBundleCache,
        defaultReviewRecord: (TCFDRunArtifactBundle) -> TCFDReviewRecord,
        normalizeReviewRecord: (TCFDReviewRecord) -> TCFDReviewRecord,
        reviewRecordNeedsRepair: (TCFDReviewRecord) -> Bool
    ) -> TCFDDiscoveryOutcome
}

protocol TCFDReviewPersistenceServicing {
    func persistIndex(_ snapshot: TCFDReviewBundleIndex, to storageURL: URL)
    func persistReviewRecord(_ record: TCFDReviewRecord, to reviewURL: URL) throws
}

protocol TCFDBoardPackExportServicing {
    func exportBoardPack(bundle: TCFDRunArtifactBundle,
                         review: TCFDReviewRecord,
                         report: String,
                         encoder: JSONEncoder) throws -> URL
}

final class TCFDBundleCache {
    private struct CachedBundle {
        var manifestModifiedAt: Date?
        var reviewModifiedAt: Date?
        var summaryModifiedAt: Date?
        var mappingModifiedAt: Date?
        var bundle: TCFDRunArtifactBundle
    }

    private let lock = NSLock()
    private var bundles: [String: CachedBundle] = [:]

    func cachedBundle(manifestURL: URL,
                      reviewRecordURL: URL,
                      summaryURL: URL,
                      mappingURL: URL) -> TCFDRunArtifactBundle? {
        let manifestPath = manifestURL.path
        let manifestModifiedAt = modificationDateIfExists(for: manifestURL)
        let reviewModifiedAt = modificationDateIfExists(for: reviewRecordURL)
        let summaryModifiedAt = modificationDateIfExists(for: summaryURL)
        let mappingModifiedAt = modificationDateIfExists(for: mappingURL)

        lock.lock()
        defer { lock.unlock() }

        guard let cached = bundles[manifestPath],
              cached.manifestModifiedAt == manifestModifiedAt,
              cached.reviewModifiedAt == reviewModifiedAt,
              cached.summaryModifiedAt == summaryModifiedAt,
              cached.mappingModifiedAt == mappingModifiedAt else {
            return nil
        }
        return cached.bundle
    }

    func cache(_ bundle: TCFDRunArtifactBundle,
               manifestURL: URL,
               reviewRecordURL: URL,
               summaryURL: URL,
               mappingURL: URL) {
        let cached = CachedBundle(
            manifestModifiedAt: modificationDateIfExists(for: manifestURL),
            reviewModifiedAt: modificationDateIfExists(for: reviewRecordURL),
            summaryModifiedAt: modificationDateIfExists(for: summaryURL),
            mappingModifiedAt: modificationDateIfExists(for: mappingURL),
            bundle: bundle
        )

        lock.lock()
        bundles[manifestURL.path] = cached
        lock.unlock()
    }

    func invalidate(manifestPath: String) {
        lock.lock()
        bundles.removeValue(forKey: manifestPath)
        lock.unlock()
    }

    func prune(keeping manifestPaths: Set<String>) {
        lock.lock()
        bundles = bundles.filter { manifestPaths.contains($0.key) }
        lock.unlock()
    }

    private func modificationDateIfExists(for url: URL) -> Date? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

struct TCFDDiscoveryOutcome {
    var bundles: [TCFDRunArtifactBundle]
    var repairedReviewRecordCount: Int
    var skippedReviewRecordCount: Int
}

final class TCFDReviewDiscoveryService: TCFDReviewDiscoveryServicing {
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func discoverBundles(
        in roots: [URL],
        cache: TCFDBundleCache,
        defaultReviewRecord: (TCFDRunArtifactBundle) -> TCFDReviewRecord,
        normalizeReviewRecord: (TCFDReviewRecord) -> TCFDReviewRecord,
        reviewRecordNeedsRepair: (TCFDReviewRecord) -> Bool
    ) -> TCFDDiscoveryOutcome {
        var discovered: [TCFDRunArtifactBundle] = []
        var seen = Set<String>()
        var discoveredManifestPaths = Set<String>()
        var repairedReviewRecordCount = 0
        var skippedReviewRecordCount = 0

        for root in roots {
            let searchRoot = normalizedSearchRoot(for: root)
            guard FileManager.default.fileExists(atPath: searchRoot.path) else { continue }
            if let enumerator = FileManager.default.enumerator(at: searchRoot,
                                                               includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator {
                    guard url.lastPathComponent == "run_manifest.json" else { continue }
                    guard let bundle = loadBundle(
                        fromManifestURL: url,
                        cache: cache,
                        defaultReviewRecord: defaultReviewRecord,
                        normalizeReviewRecord: normalizeReviewRecord,
                        reviewRecordNeedsRepair: reviewRecordNeedsRepair,
                        repairedReviewRecordCount: &repairedReviewRecordCount,
                        skippedReviewRecordCount: &skippedReviewRecordCount
                    ), seen.insert(bundle.id).inserted else {
                        continue
                    }
                    discoveredManifestPaths.insert(url.path)
                    discovered.append(bundle)
                }
            }
        }

        cache.prune(keeping: discoveredManifestPaths)
        discovered.sort { $0.generatedAt > $1.generatedAt }
        return TCFDDiscoveryOutcome(
            bundles: discovered,
            repairedReviewRecordCount: repairedReviewRecordCount,
            skippedReviewRecordCount: skippedReviewRecordCount
        )
    }

    private func normalizedSearchRoot(for root: URL) -> URL {
        if root.lastPathComponent == "_climateliberator" {
            return root
        }
        let nested = root.appendingPathComponent("_climateliberator", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
        return root
    }

    private func loadBundle(
        fromManifestURL manifestURL: URL,
        cache: TCFDBundleCache,
        defaultReviewRecord: (TCFDRunArtifactBundle) -> TCFDReviewRecord,
        normalizeReviewRecord: (TCFDReviewRecord) -> TCFDReviewRecord,
        reviewRecordNeedsRepair: (TCFDReviewRecord) -> Bool,
        repairedReviewRecordCount: inout Int,
        skippedReviewRecordCount: inout Int
    ) -> TCFDRunArtifactBundle? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(ManifestPayload.self, from: data) else {
            return nil
        }

        let bundleURL = manifestURL.deletingLastPathComponent()
        let summaryURL = URL(fileURLWithPath: manifest.summaryJSON)
        let mappingURL = URL(fileURLWithPath: manifest.tcfdMappingJSON)
        let reportURL = URL(fileURLWithPath: manifest.tcfdPilotReport)
        let reviewRecordURL = bundleURL.appendingPathComponent("review_record.json")

        if let cached = cache.cachedBundle(manifestURL: manifestURL,
                                           reviewRecordURL: reviewRecordURL,
                                           summaryURL: summaryURL,
                                           mappingURL: mappingURL) {
            return cached
        }

        let summary = loadSummary(from: summaryURL)
        let mapping = loadMapping(from: mappingURL)

        var bundle = TCFDRunArtifactBundle(
            runID: manifest.runID,
            bundleURL: bundleURL.path,
            manifestURL: manifestURL.path,
            reportURL: reportURL.path,
            summaryJSONURL: summaryURL.path,
            summaryCSVURL: manifest.summaryCSV,
            artifactIndexURL: manifest.artifactIndexJSON,
            mappingURL: mappingURL.path,
            rawStdoutURL: bundleURL.appendingPathComponent("raw_stdout.txt").path,
            rawStderrURL: bundleURL.appendingPathComponent("raw_stderr.txt").path,
            generatedAt: manifest.generatedAt,
            timestamp: manifest.completedAt,
            simulatorCode: manifest.simulatorCode,
            simulatorLabel: manifest.simulatorLabel,
            inputFolder: manifest.inputFolder,
            outputDirectory: manifest.outputDirectory,
            totalBurnt: summary?.totalBurnt,
            totalCells: summary?.totalCells,
            totalBurntPercent: summary?.totalBurntPercent,
            highestROS: summary?.highestROS,
            lowestROS: summary?.lowestROS,
            scenarioName: manifest.scenarioName,
            tcfdScenarioLabel: manifest.tcfdScenarioLabel,
            scenarioPathway: manifest.scenarioPathway,
            scenarioHorizon: manifest.scenarioHorizon,
            governanceSummary: mapping?.governance.summary ?? [],
            strategySummary: mapping?.strategy.summary ?? [],
            riskManagementSummary: mapping?.riskManagement.summary ?? [],
            metricsSummary: mapping?.metricsTargets.summary ?? [],
            reviewRecordURL: reviewRecordURL.path,
            reviewRecord: nil,
            loadedFromDisk: true
        )

        switch loadReviewRecord(from: reviewRecordURL,
                                normalizeReviewRecord: normalizeReviewRecord,
                                reviewRecordNeedsRepair: reviewRecordNeedsRepair) {
        case .loaded(let reviewRecord, let repaired):
            if repaired { repairedReviewRecordCount += 1 }
            bundle.reviewRecord = reviewRecord
        case .malformedSkipped:
            skippedReviewRecordCount += 1
            bundle.reviewRecord = defaultReviewRecord(bundle)
        case .missing:
            bundle.reviewRecord = defaultReviewRecord(bundle)
        }

        cache.cache(bundle,
                    manifestURL: manifestURL,
                    reviewRecordURL: reviewRecordURL,
                    summaryURL: summaryURL,
                    mappingURL: mappingURL)
        return bundle
    }

    private func loadSummary(from url: URL) -> SummaryPayload? {
        guard let data = try? Data(contentsOf: url),
              var summary = try? decoder.decode(SummaryPayload.self, from: data) else {
            return nil
        }
        if summary.highestROS == nil {
            summary.highestROS = summary.simulations?.compactMap(\.highestROS).max()
        }
        if summary.lowestROS == nil {
            summary.lowestROS = summary.simulations?.compactMap(\.lowestROS).min()
        }
        return summary
    }

    private func loadMapping(from url: URL) -> MappingPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(MappingPayload.self, from: data)
    }

    private func loadReviewRecord(
        from url: URL,
        normalizeReviewRecord: (TCFDReviewRecord) -> TCFDReviewRecord,
        reviewRecordNeedsRepair: (TCFDReviewRecord) -> Bool
    ) -> ReviewLoadOutcome {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(TCFDReviewRecord.self, from: data) else {
            return .malformedSkipped
        }
        let repaired = reviewRecordNeedsRepair(record)
        return .loaded(normalizeReviewRecord(record), repaired: repaired)
    }
}

final class TCFDReviewPersistenceService: TCFDReviewPersistenceServicing {
    func persistIndex(_ snapshot: TCFDReviewBundleIndex, to storageURL: URL) {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Best-effort cache only.
        }
    }

    func persistReviewRecord(_ record: TCFDReviewRecord, to reviewURL: URL) throws {
        try FileManager.default.createDirectory(at: reviewURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: reviewURL, options: .atomic)
    }
}

final class TCFDBoardPackExportService: TCFDBoardPackExportServicing {
    private struct BoardPackSummary: Codable {
        let runID: String
        let generatedAt: Date
        let sourceReportURL: String
        let boardPackReportURL: String
        let reviewStatus: ReviewStatus
        let packageState: PackageLifecycleState
        let decision: ReviewDecision
        let approver: PersonRef?
        let accountableExecutive: PersonRef?
        let dueDate: Date?
        let approvedAt: Date?
        let scenario: ReviewScenarioSnapshot
        let thresholds: ThresholdEvaluationSummary
        let thresholdBreachActions: [ThresholdBreachAction]
        let financialEffects: FinancialEffectsReview
        let conditions: [String]
        let provenance: ProvenanceSummary
    }

    func exportBoardPack(bundle: TCFDRunArtifactBundle,
                         review: TCFDReviewRecord,
                         report: String,
                         encoder: JSONEncoder) throws -> URL {
        let bundleURL = URL(fileURLWithPath: bundle.bundleURL)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let reportURL = bundleURL.appendingPathComponent("tcfd_board_pack.md")
        let summaryURL = bundleURL.appendingPathComponent("board_pack_summary.json")

        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        let summary = BoardPackSummary(
            runID: bundle.runID,
            generatedAt: Date(),
            sourceReportURL: bundle.reportURL,
            boardPackReportURL: reportURL.path,
            reviewStatus: review.reviewStatus,
            packageState: review.packageState,
            decision: review.decision,
            approver: review.approver,
            accountableExecutive: review.accountableExecutive,
            dueDate: review.dueDate,
            approvedAt: review.approvedAt,
            scenario: review.scenario,
            thresholds: review.thresholds,
            thresholdBreachActions: review.thresholdBreachActions ?? [],
            financialEffects: review.financialEffects,
            conditions: review.conditions,
            provenance: review.provenance
        )
        let data = try encoder.encode(summary)
        try data.write(to: summaryURL, options: .atomic)
        return reportURL
    }
}

private enum ReviewLoadOutcome {
    case missing
    case malformedSkipped
    case loaded(TCFDReviewRecord, repaired: Bool)
}

private struct ManifestPayload: Codable {
    let runID: String
    let appVersion: String
    let generatedAt: Date
    let startedAt: Date
    let completedAt: Date
    let durationSeconds: Double
    let binaryPath: String
    let binaryHash: String?
    let inputFolder: String
    let outputDirectory: String
    let logFilePath: String?
    let simulatorCode: String
    let simulatorLabel: String
    let scenarioName: String?
    let tcfdScenarioLabel: String?
    let scenarioPathway: String?
    let scenarioHorizon: String?
    let includeROS: Bool
    let weatherPeriodMinutes: Int
    let outputFormat: String
    let numberOfSimulations: Int
    let numberOfThreads: Int
    let seed: Int
    let summaryJSON: String
    let summaryCSV: String
    let artifactIndexJSON: String
    let tcfdMappingJSON: String
    let tcfdPilotReport: String
}

private struct SummaryPayload: Codable {
    struct Simulation: Codable {
        let highestROS: Double?
        let lowestROS: Double?
    }

    var runID: String
    var timestamp: Date
    var totalBurnt: Int?
    var totalCells: Int?
    var totalBurntPercent: Double?
    var highestROS: Double?
    var lowestROS: Double?
    var simulations: [Simulation]?
}

private struct MappingPayload: Codable {
    struct Section: Codable {
        let summary: [String]
    }

    let runID: String
    let generatedAt: Date
    let governance: Section
    let strategy: Section
    let riskManagement: Section
    let metricsTargets: Section
}
