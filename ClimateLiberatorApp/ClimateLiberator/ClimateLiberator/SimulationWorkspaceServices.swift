import Foundation
import Combine

struct OperationalRunConfigDocument: Codable {
    let schemaVersion: Int
    let hazardType: String
    let exportedAt: Date
    let binaryPath: String
    let inputFolder: String
    let outputFolder: String
    let simulatorCode: String
    let includeROS: Bool
    let weatherPeriodMinutes: Int
    let outputFormat: String
    let numberOfSimulations: Int
    let numberOfThreads: Int
    let seed: Int
    let selectedScenarioID: UUID?
    let scenarioName: String?
    let tcfdScenarioLabel: String?
    let scenarioPathway: String?
    let scenarioHorizon: String?
}

struct OutputNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [OutputNode]?

    nonisolated init(name: String, url: URL, isDirectory: Bool, children: [OutputNode]?) {
        self.id = "\(url.path)#\(name)"
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    nonisolated var isSelectable: Bool {
        !isDirectory && url.pathExtension.lowercased() == "asc"
    }

    nonisolated var iconName: String {
        isDirectory ? "folder" : "square.stack.3d.up"
    }
}

struct OutputTreeDiscoveryLimits {
    let maxDepth: Int
    let maxNodes: Int
}

private struct OutputTreeDiscoveryState: Sendable {
    var emittedNodeCount = 0
    var didHitLimit = false

    nonisolated init(emittedNodeCount: Int = 0, didHitLimit: Bool = false) {
        self.emittedNodeCount = emittedNodeCount
        self.didHitLimit = didHitLimit
    }
}

protocol SimulationRunConfigServicing {
    func exportData(for document: OperationalRunConfigDocument) throws -> Data
    func importDocument(from url: URL) throws -> OperationalRunConfigDocument
    func exportFileName(at date: Date) -> String
}

struct SimulationRunConfigService: SimulationRunConfigServicing {
    func exportData(for document: OperationalRunConfigDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    func importDocument(from url: URL) throws -> OperationalRunConfigDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OperationalRunConfigDocument.self, from: data)
    }

    func exportFileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "climateliberator-run-config-\(formatter.string(from: date)).json"
    }
}

protocol SimulationReviewDiscoveryServicing: Sendable {
    func discoveryRoots(for outputFolder: String) -> [URL]
}

struct SimulationReviewDiscoveryService: SimulationReviewDiscoveryServicing, Sendable {
    nonisolated func discoveryRoots(for outputFolder: String) -> [URL] {
        let trimmed = outputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let resolved = NSString(string: trimmed).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: resolved)
        let bundleRoot = rootURL.appendingPathComponent("_climateliberator", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleRoot.path) {
            return [bundleRoot]
        }
        return [rootURL]
    }
}

protocol SimulationOutputTreeServicing: Sendable {
    func buildOutputTree(rateOfSpreadBase: String?,
                         earthEngineOverlaysDirectory: URL?,
                         limits: OutputTreeDiscoveryLimits) -> [OutputNode]
}

struct SimulationOutputTreeService: SimulationOutputTreeServicing, Sendable {
    nonisolated func buildOutputTree(rateOfSpreadBase: String?,
                                     earthEngineOverlaysDirectory: URL?,
                                     limits: OutputTreeDiscoveryLimits) -> [OutputNode] {
        var nodes: [OutputNode] = []
        var discoveryState = OutputTreeDiscoveryState()

        if let path = rateOfSpreadBase {
            let rosDir = rateOfSpreadDirectory(basePath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: rosDir.path, isDirectory: &isDir),
               isDir.boolValue {
                let children = buildOutputNodes(at: rosDir,
                                                depth: 0,
                                                limits: limits,
                                                state: &discoveryState)
                if !children.isEmpty {
                    nodes.append(OutputNode(name: rosDir.lastPathComponent,
                                            url: rosDir,
                                            isDirectory: true,
                                            children: children))
                }
            }
        }

        if let earthEngineOverlaysDirectory {
            let children = buildOutputNodes(at: earthEngineOverlaysDirectory,
                                            depth: 0,
                                            limits: limits,
                                            state: &discoveryState)
            if !children.isEmpty {
                nodes.append(OutputNode(name: "Earth Engine Imports",
                                        url: earthEngineOverlaysDirectory,
                                        isDirectory: true,
                                        children: children))
            }
        }

        return nodes
    }

    nonisolated private func rateOfSpreadDirectory(basePath: String) -> URL {
        let baseURL = URL(fileURLWithPath: basePath)
        if baseURL.lastPathComponent.compare("RateOfSpread", options: .caseInsensitive) == .orderedSame {
            return baseURL
        }
        return baseURL.appendingPathComponent("RateOfSpread")
    }

    nonisolated private func buildOutputNodes(at directory: URL,
                                              depth: Int,
                                              limits: OutputTreeDiscoveryLimits,
                                              state: inout OutputTreeDiscoveryState) -> [OutputNode] {
        guard depth <= limits.maxDepth, !state.didHitLimit else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory,
                                                         includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                         options: [.skipsHiddenFiles]) else {
            return []
        }

        var nodes: [OutputNode] = []
        nodes.reserveCapacity(min(contents.count, 64))

        for url in contents {
            guard !state.didHitLimit else { break }
            if state.emittedNodeCount >= limits.maxNodes {
                state.didHitLimit = true
                break
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                continue
            }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let children = buildOutputNodes(at: url,
                                                depth: depth + 1,
                                                limits: limits,
                                                state: &state)
                if !children.isEmpty {
                    state.emittedNodeCount += 1
                    nodes.append(OutputNode(name: url.lastPathComponent,
                                            url: url,
                                            isDirectory: true,
                                            children: children))
                }
            } else {
                guard url.pathExtension.lowercased() == "asc" else { continue }
                state.emittedNodeCount += 1
                nodes.append(OutputNode(name: url.lastPathComponent,
                                        url: url,
                                        isDirectory: false,
                                        children: nil))
            }
        }

        if state.didHitLimit {
            nodes.append(OutputNode(name: "More outputs not shown…",
                                    url: directory,
                                    isDirectory: false,
                                    children: nil))
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

@MainActor
final class SimulationOutputStore: ObservableObject {
    @Published private(set) var nodes: [OutputNode] = []
    @Published private(set) var isLoading = false

    private let treeService: any SimulationOutputTreeServicing
    private var loadToken: UInt = 0

    init(treeService: any SimulationOutputTreeServicing) {
        self.treeService = treeService
    }

    func rebuild(rateOfSpreadBase: String?,
                 earthEngineOverlaysDirectory: URL?,
                 limits: OutputTreeDiscoveryLimits) {
        loadToken &+= 1
        let token = loadToken
        isLoading = true
        let treeService = self.treeService
        DispatchQueue.global(qos: .userInitiated).async {
            let nodes = treeService.buildOutputTree(rateOfSpreadBase: rateOfSpreadBase,
                                                    earthEngineOverlaysDirectory: earthEngineOverlaysDirectory,
                                                    limits: limits)
            DispatchQueue.main.async {
                guard token == self.loadToken else { return }
                self.nodes = nodes
                self.isLoading = false
            }
        }
    }

    func clearLoadingState() {
        isLoading = false
    }
}
