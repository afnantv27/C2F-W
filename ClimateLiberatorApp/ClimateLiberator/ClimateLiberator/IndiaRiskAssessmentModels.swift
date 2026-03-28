import Foundation

struct IndiaWildfireRiskGrid {
    let width: Int
    let height: Int
    let minLon: Double
    let maxLon: Double
    let minLat: Double
    let maxLat: Double
    let maxValue: Double
    let values: [Double?]

    var lonCellSize: Double {
        guard width > 0 else { return 0 }
        return (maxLon - minLon) / Double(width)
    }

    var latCellSize: Double {
        guard height > 0 else { return 0 }
        return (maxLat - minLat) / Double(height)
    }

    func sampledValue(latitude: Double, longitude: Double) -> Double? {
        guard width > 0, height > 0, lonCellSize > 0, latCellSize > 0 else { return nil }
        guard longitude >= minLon, longitude <= maxLon, latitude >= minLat, latitude <= maxLat else { return nil }

        let rawColumn = Int((longitude - minLon) / lonCellSize)
        let rawRow = Int((maxLat - latitude) / latCellSize)
        let column = min(max(rawColumn, 0), width - 1)
        let row = min(max(rawRow, 0), height - 1)
        let index = row * width + column
        guard index >= 0, index < values.count else { return nil }
        return values[index]
    }

    func activeCells() -> [IndiaWildfireActiveCell] {
        guard width > 0, height > 0, lonCellSize > 0, latCellSize > 0 else { return [] }

        var cells: [IndiaWildfireActiveCell] = []
        cells.reserveCapacity(values.count / 8)

        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                guard index < values.count, let value = values[index], value > 0 else { continue }

                let longitude = minLon + (Double(column) + 0.5) * lonCellSize
                let latitude = maxLat - (Double(row) + 0.5) * latCellSize
                cells.append(IndiaWildfireActiveCell(latitude: latitude, longitude: longitude, intensity: value))
            }
        }

        return cells
    }
}

struct IndiaWildfireRiskLinkRequest {
    let runID: String
    let scenarioLabel: String
    let simulatorLabel: String
    let siteLatitude: Double
    let siteLongitude: Double
    let searchRadiusMeters: Double
    let outputDirectory: String
    let sourceRasterPath: String
    let ignitionCell: Int?
}

struct IndiaWildfireRiskLinkResult {
    let candidateCount: Int
    let storedCount: Int
    let highRiskCount: Int
    let mediumRiskCount: Int
    let lowRiskCount: Int
}

struct IndiaWildfireActiveCell {
    let latitude: Double
    let longitude: Double
    let intensity: Double
}
