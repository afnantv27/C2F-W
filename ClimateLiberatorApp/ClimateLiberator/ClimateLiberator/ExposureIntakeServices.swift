import Foundation
import AppKit
import UniformTypeIdentifiers

struct CanonicalExposurePortfolio: Codable, Hashable {
    var standard: String
    var importedAt: Date
    var sourcePath: String
    var locationFilePath: String
    var accountFilePath: String? = nil
    var riInfoFilePath: String? = nil
    var riScopeFilePath: String? = nil
    var locations: [CanonicalExposureLocation]
    var accounts: [CanonicalExposureAccount]
}

struct CanonicalExposureLocation: Identifiable, Codable, Hashable {
    var id: String
    var perilCode: String
    var coverageTypeID: String?
    var areaPerilID: String?
    var vulnerabilityID: String?
    var assetName: String?
    var latitude: Double?
    var longitude: Double?
    var occupancyCode: String?
    var constructionCode: String?
    var buildingTIV: Double?
    var contentsTIV: Double?
    var businessInterruptionTIV: Double?
    var currencyCode: String?
    var accountReference: String?
}

struct CanonicalExposureAccount: Identifiable, Codable, Hashable {
    var id: String
    var portfolioReference: String?
    var accountName: String?
    var currencyCode: String?
}

enum ExposureValidationSeverity: String, Codable, CaseIterable, Hashable {
    case critical
    case warning
    case info
}

struct ExposureValidationIssue: Identifiable, Codable, Hashable {
    var id = UUID()
    var severity: ExposureValidationSeverity
    var message: String
}

struct ExposureImportSummary: Codable, Hashable {
    var standard: String
    var sourceLabel: String
    var locationCount: Int
    var accountCount: Int
    var hasRIInfo: Bool
    var hasRIScope: Bool
    var perilCodes: [String]
    var currencyCodes: [String]
    var totalBuildingTIV: Double
    var totalContentsTIV: Double
    var totalBusinessInterruptionTIV: Double
    var geocodedLocationCount: Int
    var financialLocationCount: Int
    var validationIssues: [ExposureValidationIssue]
}

struct ExposureImportArtifact: Identifiable, Codable, Hashable {
    var id: String { artifactPath }
    var artifactPath: String
    var sourcePath: String
    var importedAt: Date
    var summary: ExposureImportSummary
}

struct ExposurePortfolioCodeBreakdown: Identifiable, Codable, Hashable {
    var id: String { code }
    var code: String
    var count: Int
}

struct ExposureLocationPreview: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var perilCode: String
    var coordinateLabel: String?
    var accountReference: String?
}

struct ExposurePortfolioOverview: Codable, Hashable {
    var locationCount: Int
    var accountCount: Int
    var geocodedLocationCount: Int
    var financialLocationCount: Int
    var totalInsuredValue: Double
    var perilMix: [ExposurePortfolioCodeBreakdown]
    var occupancyMix: [ExposurePortfolioCodeBreakdown]
    var constructionMix: [ExposurePortfolioCodeBreakdown]
    var currencyCodes: [String]
    var sampleLocations: [ExposureLocationPreview]
    var hasReinsuranceStructure: Bool
}

enum ExposureImportError: LocalizedError {
    case selectionCancelled
    case invalidSource(message: String)
    case parseFailed(message: String)
    case writeFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .selectionCancelled:
            return "Exposure import was cancelled."
        case .invalidSource(let message), .parseFailed(let message), .writeFailed(let message):
            return message
        }
    }
}

protocol ExposureImportPathSelecting {
    func selectOEDSourcePath() -> String?
}

protocol ExposurePackageImporting {
    func importOEDPackage(from sourcePath: String) throws -> ExposureImportArtifact
}

protocol ExposureImportArtifactLoading {
    func loadLatestPersistedImport() throws -> PersistedExposureImport?
}

protocol ExposurePortfolioOverviewBuilding {
    func makeOverview(from persistedImport: PersistedExposureImport) -> ExposurePortfolioOverview
}

struct OEDImportPathSelector: ExposureImportPathSelecting {
    func selectOEDSourcePath() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Select OED Exposure Source"
        panel.message = "Choose an OED folder or a Location CSV file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .commaSeparatedText, .plainText]
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct OEDExposureImportService: ExposurePackageImporting {
    private let artifactDirectory: String
    private let now: () -> Date

    init(artifactDirectory: String = ExposureIntakeStore.defaultArtifactDirectory(),
         now: @escaping () -> Date = Date.init) {
        self.artifactDirectory = artifactDirectory
        self.now = now
    }

    func importOEDPackage(from sourcePath: String) throws -> ExposureImportArtifact {
        let resolvedSourcePath = NSString(string: sourcePath).expandingTildeInPath
        let sourceURL = URL(fileURLWithPath: resolvedSourcePath)
        let sourceType = classifySource(at: sourceURL)
        let files = try resolveOEDFiles(from: sourceURL, sourceType: sourceType)

        let locationDataset = try loadCSV(url: files.locationURL, label: "Location")
        let locationIssues = validateLocationHeaders(locationDataset.headers)
        guard !locationIssues.contains(where: { $0.severity == .critical }) else {
            throw ExposureImportError.invalidSource(message: locationIssues.map(\.message).joined(separator: " "))
        }

        let accountDataset = try files.accountURL.map { try loadCSV(url: $0, label: "Account") }
        let accountIssues = validateAccountHeaders(accountDataset?.headers ?? [])

        let locations = parseLocations(from: locationDataset)
        guard !locations.isEmpty else {
            throw ExposureImportError.parseFailed(message: "The selected OED source did not contain any valid location rows.")
        }
        let accounts = parseAccounts(from: accountDataset)

        let validationIssues = locationIssues + accountIssues + deriveLocationIssues(from: locations)
        let portfolio = CanonicalExposurePortfolio(
            standard: "OED",
            importedAt: now(),
            sourcePath: resolvedSourcePath,
            locationFilePath: files.locationURL.path,
            accountFilePath: files.accountURL?.path,
            riInfoFilePath: files.riInfoURL?.path,
            riScopeFilePath: files.riScopeURL?.path,
            locations: locations,
            accounts: accounts
        )
        let summary = buildSummary(
            sourceType: sourceType,
            locations: locations,
            accounts: accounts,
            hasRIInfo: files.riInfoURL != nil,
            hasRIScope: files.riScopeURL != nil,
            issues: validationIssues
        )

        do {
            try FileManager.default.createDirectory(atPath: artifactDirectory, withIntermediateDirectories: true)
            let fileName = "oed_import_\(ExposureTimestampFormatter.compact.string(from: now())).json"
            let artifactPath = (artifactDirectory as NSString).appendingPathComponent(fileName)
            let artifact = ExposureImportArtifact(
                artifactPath: artifactPath,
                sourcePath: resolvedSourcePath,
                importedAt: portfolio.importedAt,
                summary: summary
            )
            let payload = PersistedExposureImport(artifact: artifact, portfolio: portfolio)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(payload).write(to: URL(fileURLWithPath: artifactPath), options: .atomic)
            return artifact
        } catch {
            throw ExposureImportError.writeFailed(message: "Could not persist the OED intake artifact.")
        }
    }

    private func classifySource(at url: URL) -> SourceType {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .directory
        }
        return .singleLocationFile
    }

    private func resolveOEDFiles(from sourceURL: URL,
                                 sourceType: SourceType) throws -> ResolvedOEDFiles {
        switch sourceType {
        case .singleLocationFile:
            guard sourceURL.pathExtension.lowercased() == "csv" || sourceURL.pathExtension.lowercased() == "txt" else {
                throw ExposureImportError.invalidSource(message: "Select an OED folder or a CSV/text Location file.")
            }
            return ResolvedOEDFiles(locationURL: sourceURL, accountURL: nil, riInfoURL: nil, riScopeURL: nil)
        case .directory:
            let entries = try FileManager.default.contentsOfDirectory(at: sourceURL,
                                                                      includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles])
            let csvEntries = entries.filter { ["csv", "txt"].contains($0.pathExtension.lowercased()) }
            guard !csvEntries.isEmpty else {
                throw ExposureImportError.invalidSource(message: "The selected folder does not contain any OED CSV/text files.")
            }

            func candidate(containing tokens: [String]) -> URL? {
                csvEntries.first { entry in
                    let name = entry.deletingPathExtension().lastPathComponent.lowercased()
                    return tokens.contains { name.contains($0) }
                }
            }

            guard let locationURL = candidate(containing: ["location", "locations", "loc"]) else {
                throw ExposureImportError.invalidSource(message: "The selected folder does not contain an OED Location file.")
            }

            return ResolvedOEDFiles(
                locationURL: locationURL,
                accountURL: candidate(containing: ["account", "accounts", "acc"]),
                riInfoURL: candidate(containing: ["riinfo", "reinsuranceinfo", "reinsinfo"]),
                riScopeURL: candidate(containing: ["riscope", "reinsscope"])
            )
        }
    }

    private func loadCSV(url: URL, label: String) throws -> CSVDataSet {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExposureImportError.parseFailed(message: "Could not read the \(label) file at \(url.path).")
        }
        let rows = CSVParser.parse(content)
        guard let headerRow = rows.first, !headerRow.isEmpty else {
            throw ExposureImportError.parseFailed(message: "The \(label) file is empty.")
        }
        let headers = headerRow.map { normalizedHeader($0) }
        let dataRows = Array(rows.dropFirst()).filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        return CSVDataSet(headers: headers, rows: dataRows)
    }

    private func validateLocationHeaders(_ headers: [String]) -> [ExposureValidationIssue] {
        var issues: [ExposureValidationIssue] = []
        let required = ["locid", "perilid"]
        for header in required where !headers.contains(header) {
            issues.append(ExposureValidationIssue(severity: .critical, message: "OED Location file is missing required column '\(header)'."))
        }
        if !headers.contains("latitude") || !headers.contains("longitude") {
            issues.append(ExposureValidationIssue(severity: .warning, message: "Location coordinates are incomplete. Mapping and hazard linkage will be limited."))
        }
        if !headers.contains(where: { ["tiv_building", "tivcontents", "tiv_contents", "tiv"].contains($0) }) {
            issues.append(ExposureValidationIssue(severity: .warning, message: "No building or contents TIV columns were found. Financial analytics may require proxy values or enrichment."))
        }
        return issues
    }

    private func validateAccountHeaders(_ headers: [String]) -> [ExposureValidationIssue] {
        guard !headers.isEmpty else { return [] }
        var issues: [ExposureValidationIssue] = []
        if !headers.contains(where: { ["accnumber", "accountid", "portnumber"].contains($0) }) {
            issues.append(ExposureValidationIssue(severity: .warning, message: "Account file is present but does not expose a standard account identifier column."))
        }
        return issues
    }

    private func parseLocations(from dataset: CSVDataSet) -> [CanonicalExposureLocation] {
        dataset.rows.compactMap { row in
            let table = table(for: dataset.headers, row: row)
            guard let locID = value(in: table, keys: ["locid"]), !locID.isEmpty,
                  let perilID = value(in: table, keys: ["perilid"]), !perilID.isEmpty else {
                return nil
            }
            return CanonicalExposureLocation(
                id: locID,
                perilCode: perilID,
                coverageTypeID: value(in: table, keys: ["coveragetypeid"]),
                areaPerilID: value(in: table, keys: ["areaperilid"]),
                vulnerabilityID: value(in: table, keys: ["vulnerabilityid"]),
                assetName: value(in: table, keys: ["assetname", "locationname", "locname"]),
                latitude: numericValue(in: table, keys: ["latitude", "lat"]),
                longitude: numericValue(in: table, keys: ["longitude", "lon", "long"]),
                occupancyCode: value(in: table, keys: ["occupancycode", "occupancy"]),
                constructionCode: value(in: table, keys: ["constructioncode", "construction"]),
                buildingTIV: numericValue(in: table, keys: ["tiv_building", "buildingtiv", "tiv"]),
                contentsTIV: numericValue(in: table, keys: ["tiv_contents", "contentstiv"]),
                businessInterruptionTIV: numericValue(in: table, keys: ["tiv_bi", "bitiv", "businessinterruptiontiv"]),
                currencyCode: value(in: table, keys: ["currencycode", "currency"]),
                accountReference: value(in: table, keys: ["accnumber", "accountid", "portnumber"])
            )
        }
    }

    private func parseAccounts(from dataset: CSVDataSet?) -> [CanonicalExposureAccount] {
        guard let dataset else { return [] }
        return dataset.rows.compactMap { row in
            let table = table(for: dataset.headers, row: row)
            guard let accountID = value(in: table, keys: ["accnumber", "accountid", "portnumber"]), !accountID.isEmpty else {
                return nil
            }
            return CanonicalExposureAccount(
                id: accountID,
                portfolioReference: value(in: table, keys: ["portnumber", "portfolioid"]),
                accountName: value(in: table, keys: ["accname", "accountname", "insuredname"]),
                currencyCode: value(in: table, keys: ["currencycode", "currency"])
            )
        }
    }

    private func deriveLocationIssues(from locations: [CanonicalExposureLocation]) -> [ExposureValidationIssue] {
        var issues: [ExposureValidationIssue] = []
        let geocodedCount = locations.filter { $0.latitude != nil && $0.longitude != nil }.count
        if geocodedCount < locations.count {
            issues.append(ExposureValidationIssue(severity: .warning, message: "\(locations.count - geocodedCount) location row(s) are missing latitude/longitude."))
        }
        let financialCount = locations.filter { ($0.buildingTIV ?? 0) > 0 || ($0.contentsTIV ?? 0) > 0 || ($0.businessInterruptionTIV ?? 0) > 0 }.count
        if financialCount == 0 {
            issues.append(ExposureValidationIssue(severity: .warning, message: "No financial values were populated in the imported OED locations."))
        }
        return issues
    }

    private func buildSummary(sourceType: SourceType,
                              locations: [CanonicalExposureLocation],
                              accounts: [CanonicalExposureAccount],
                              hasRIInfo: Bool,
                              hasRIScope: Bool,
                              issues: [ExposureValidationIssue]) -> ExposureImportSummary {
        let perilCodes = Set(locations.map(\.perilCode).filter { !$0.isEmpty })
        let currencyCodes = Set((locations.compactMap(\.currencyCode) + accounts.compactMap(\.currencyCode)).filter { !$0.isEmpty })
        let buildingTIV = locations.reduce(0) { $0 + max($1.buildingTIV ?? 0, 0) }
        let contentsTIV = locations.reduce(0) { $0 + max($1.contentsTIV ?? 0, 0) }
        let biTIV = locations.reduce(0) { $0 + max($1.businessInterruptionTIV ?? 0, 0) }
        let geocodedCount = locations.filter { $0.latitude != nil && $0.longitude != nil }.count
        let financialCount = locations.filter { ($0.buildingTIV ?? 0) > 0 || ($0.contentsTIV ?? 0) > 0 || ($0.businessInterruptionTIV ?? 0) > 0 }.count

        return ExposureImportSummary(
            standard: "OED",
            sourceLabel: sourceType == .directory ? "Folder package" : "Location file",
            locationCount: locations.count,
            accountCount: accounts.count,
            hasRIInfo: hasRIInfo,
            hasRIScope: hasRIScope,
            perilCodes: Array(perilCodes).sorted(),
            currencyCodes: Array(currencyCodes).sorted(),
            totalBuildingTIV: buildingTIV,
            totalContentsTIV: contentsTIV,
            totalBusinessInterruptionTIV: biTIV,
            geocodedLocationCount: geocodedCount,
            financialLocationCount: financialCount,
            validationIssues: issues
        )
    }

    private func table(for headers: [String], row: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(headers, row + Array(repeating: "", count: max(0, headers.count - row.count))))
    }

    private func value(in table: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func numericValue(in table: [String: String], keys: [String]) -> Double? {
        guard let raw = value(in: table, keys: keys) else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    private func normalizedHeader(_ header: String) -> String {
        header.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private struct CSVDataSet {
        let headers: [String]
        let rows: [[String]]
    }

    private struct ResolvedOEDFiles {
        let locationURL: URL
        let accountURL: URL?
        let riInfoURL: URL?
        let riScopeURL: URL?
    }

    private enum SourceType {
        case directory
        case singleLocationFile
    }
}

struct FileExposureImportArtifactLoader: ExposureImportArtifactLoading {
    let artifactDirectory: String

    init(artifactDirectory: String = ExposureIntakeStore.defaultArtifactDirectory()) {
        self.artifactDirectory = artifactDirectory
    }

    func loadLatestPersistedImport() throws -> PersistedExposureImport? {
        let directoryURL = URL(fileURLWithPath: artifactDirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return nil
        }

        let files = try FileManager.default.contentsOfDirectory(at: directoryURL,
                                                                includingPropertiesForKeys: [.contentModificationDateKey],
                                                                options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payloads = try files.compactMap { fileURL -> PersistedExposureImport? in
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(PersistedExposureImport.self, from: data)
        }

        guard let latestPayload = payloads.max(by: { lhs, rhs in
            if lhs.artifact.importedAt == rhs.artifact.importedAt {
                return lhs.artifact.artifactPath < rhs.artifact.artifactPath
            }
            return lhs.artifact.importedAt < rhs.artifact.importedAt
        }) else {
            return nil
        }
        return latestPayload
    }
}

struct ExposurePortfolioOverviewBuilder: ExposurePortfolioOverviewBuilding {
    func makeOverview(from persistedImport: PersistedExposureImport) -> ExposurePortfolioOverview {
        let locations = persistedImport.portfolio.locations

        return ExposurePortfolioOverview(
            locationCount: locations.count,
            accountCount: persistedImport.portfolio.accounts.count,
            geocodedLocationCount: locations.filter { $0.latitude != nil && $0.longitude != nil }.count,
            financialLocationCount: locations.filter {
                ($0.buildingTIV ?? 0) > 0 || ($0.contentsTIV ?? 0) > 0 || ($0.businessInterruptionTIV ?? 0) > 0
            }.count,
            totalInsuredValue: locations.reduce(0) {
                $0 + max($1.buildingTIV ?? 0, 0) + max($1.contentsTIV ?? 0, 0) + max($1.businessInterruptionTIV ?? 0, 0)
            },
            perilMix: buildBreakdown(from: locations.compactMap { $0.perilCode.isEmpty ? nil : $0.perilCode }),
            occupancyMix: buildBreakdown(from: locations.compactMap(\.occupancyCode)),
            constructionMix: buildBreakdown(from: locations.compactMap(\.constructionCode)),
            currencyCodes: Array(Set(locations.compactMap(\.currencyCode).filter { !$0.isEmpty })).sorted(),
            sampleLocations: Array(locations.prefix(4)).map { location in
                ExposureLocationPreview(
                    id: location.id,
                    name: location.assetName ?? location.id,
                    perilCode: location.perilCode,
                    coordinateLabel: coordinateLabel(for: location),
                    accountReference: location.accountReference
                )
            },
            hasReinsuranceStructure: persistedImport.artifact.summary.hasRIInfo || persistedImport.artifact.summary.hasRIScope
        )
    }

    private func buildBreakdown(from values: [String]) -> [ExposurePortfolioCodeBreakdown] {
        Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
            .map { ExposurePortfolioCodeBreakdown(code: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.code < rhs.code
                }
                return lhs.count > rhs.count
            }
    }

    private func coordinateLabel(for location: CanonicalExposureLocation) -> String? {
        guard let latitude = location.latitude, let longitude = location.longitude else {
            return nil
        }
        return String(format: "%.3f, %.3f", latitude, longitude)
    }
}

struct PersistedExposureImport: Codable {
    let artifact: ExposureImportArtifact
    let portfolio: CanonicalExposurePortfolio
}

private enum ExposureTimestampFormatter {
    static let compact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()

        while let char = iterator.next() {
            switch char {
            case "\"":
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            handleDelimiterCandidate(next, row: &row, field: &field, rows: &rows, inQuotes: &inQuotes)
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            case ",", "\n", "\r":
                if inQuotes {
                    field.append(char)
                } else {
                    finalize(char, row: &row, field: &field, rows: &rows)
                }
            default:
                field.append(char)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func handleDelimiterCandidate(_ char: Character,
                                                 row: inout [String],
                                                 field: inout String,
                                                 rows: inout [[String]],
                                                 inQuotes: inout Bool) {
        switch char {
        case ",", "\n", "\r":
            finalize(char, row: &row, field: &field, rows: &rows)
        case "\"":
            inQuotes = true
        default:
            field.append(char)
        }
    }

    private static func finalize(_ delimiter: Character,
                                 row: inout [String],
                                 field: inout String,
                                 rows: inout [[String]]) {
        if delimiter == "," {
            row.append(field)
            field = ""
            return
        }

        if delimiter == "\r" {
            row.append(field)
            field = ""
            if !row.isEmpty {
                rows.append(row)
            }
            row = []
            return
        }

        if delimiter == "\n" {
            row.append(field)
            field = ""
            if !row.isEmpty {
                rows.append(row)
            }
            row = []
        }
    }
}
