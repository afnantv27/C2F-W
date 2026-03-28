import Foundation

final class IndiaWildfireRiskLinker {
    private let store: IndiaRiskStore

    init(store: IndiaRiskStore) {
        self.store = store
    }

    func persistLatestWildfireAssessments(request: IndiaWildfireRiskLinkRequest,
                                          grid: IndiaWildfireRiskGrid) throws -> IndiaWildfireRiskLinkResult? {
        guard store.databaseAvailability.isEnabled else {
            return nil
        }
        return try store.persistWildfireAssessments(request: request, grid: grid)
    }
}
