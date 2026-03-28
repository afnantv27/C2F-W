import Foundation
import Combine

final class ExposureIntakeStore: ObservableObject {
    private let queue = DispatchQueue(label: "com.climateliberator.exposure-intake", qos: .userInitiated)
    private let pathSelector: ExposureImportPathSelecting
    private let importer: ExposurePackageImporting
    private let artifactLoader: ExposureImportArtifactLoading
    private let overviewBuilder: ExposurePortfolioOverviewBuilding

    @Published private(set) var lastImport: ExposureImportArtifact?
    @Published private(set) var latestPortfolio: CanonicalExposurePortfolio?
    @Published private(set) var latestOverview: ExposurePortfolioOverview?
    @Published private(set) var statusMessage = "Exposure intake ready."
    @Published private(set) var isImporting = false

    init(pathSelector: ExposureImportPathSelecting = OEDImportPathSelector(),
         importer: ExposurePackageImporting = OEDExposureImportService(),
         artifactLoader: ExposureImportArtifactLoading = FileExposureImportArtifactLoader(),
         overviewBuilder: ExposurePortfolioOverviewBuilding = ExposurePortfolioOverviewBuilder()) {
        self.pathSelector = pathSelector
        self.importer = importer
        self.artifactLoader = artifactLoader
        self.overviewBuilder = overviewBuilder
        loadLatestPersistedImport()
    }

    var latestImportAvailability: ActionAvailability {
        guard let importArtifact = lastImport else {
            return .unavailable("No persisted OED intake artifact is available yet.")
        }
        return AppActionSupport.pathAvailability(
            path: importArtifact.artifactPath,
            expectation: .file,
            emptyReason: "No persisted OED intake artifact is available yet.",
            missingReason: "The latest OED intake artifact no longer exists on disk."
        )
    }

    func importOEDPackage() {
        guard let selectedPath = pathSelector.selectOEDSourcePath() else {
            statusMessage = ExposureImportError.selectionCancelled.localizedDescription
            return
        }
        importOEDPackage(from: selectedPath)
    }

    func importOEDPackage(from sourcePath: String) {
        isImporting = true
        statusMessage = "Importing OED exposure package…"

        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.importer.importOEDPackage(from: sourcePath)
                let persistedImport = try self.artifactLoader.loadLatestPersistedImport()
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.applyPersistedImport(persistedImport)
                    if let artifact = persistedImport?.artifact {
                        self.statusMessage = "Imported \(artifact.summary.locationCount) OED location row(s) with \(artifact.summary.accountCount) account row(s)."
                    } else {
                        self.statusMessage = "Imported the OED package, but the persisted artifact could not be reloaded."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func openLatestImportArtifact() {
        guard let path = lastImport?.artifactPath else {
            statusMessage = "No persisted OED intake artifact is available yet."
            return
        }
        if !AppActionSupport.openExistingPath(path, expectation: .file) {
            statusMessage = "The latest OED intake artifact could not be opened."
        }
    }

    static func defaultArtifactDirectory() -> String {
        NSString(string: "~/Documents/ClimateLiberator/_climateliberator/exposure-intake").expandingTildeInPath
    }

    private func loadLatestPersistedImport() {
        queue.async { [weak self] in
            guard let self else { return }
            let persistedImport = try? self.artifactLoader.loadLatestPersistedImport()
            DispatchQueue.main.async {
                self.applyPersistedImport(persistedImport)
                if let artifact = persistedImport?.artifact {
                    self.statusMessage = "Loaded the latest OED intake artifact with \(artifact.summary.locationCount) location row(s)."
                }
            }
        }
    }

    private func applyPersistedImport(_ persistedImport: PersistedExposureImport?) {
        lastImport = persistedImport?.artifact
        latestPortfolio = persistedImport?.portfolio
        latestOverview = persistedImport.map { overviewBuilder.makeOverview(from: $0) }
    }
}
