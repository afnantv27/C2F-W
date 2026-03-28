import XCTest
@testable import ClimateLiberator

@MainActor
final class ClimateLiberatorPerformanceTests: XCTestCase {
    func testSimulationOutputTreeBuildPerformance() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rosDir = tempRoot.appendingPathComponent("RateOfSpread", isDirectory: true)
        let overlaysDir = tempRoot.appendingPathComponent("overlays", isDirectory: true)
        try FileManager.default.createDirectory(at: rosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: overlaysDir, withIntermediateDirectories: true)

        for index in 0..<120 {
            let fileName = String(format: "ROSFile%03d.asc", index)
            try "ncols 2\nnrows 2\nxllcorner 0\nyllcorner 0\ncellsize 1\nNODATA_value -9999\n1 2\n3 4\n"
                .write(to: rosDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }
        for index in 0..<30 {
            let fileName = String(format: "overlay%03d.asc", index)
            try "ncols 2\nnrows 2\nxllcorner 0\nyllcorner 0\ncellsize 1\nNODATA_value -9999\n1 2\n3 4\n"
                .write(to: overlaysDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }

        let service = SimulationOutputTreeService()
        measure(metrics: [XCTClockMetric()]) {
            _ = service.buildOutputTree(rateOfSpreadBase: tempRoot.path,
                                        earthEngineOverlaysDirectory: overlaysDir,
                                        limits: OutputTreeDiscoveryLimits(maxDepth: 4, maxNodes: 300))
        }
    }

    func testForecastMetricCardBuilderPerformance() {
        let builder = ForecastMetricCardBuilder()
        let weather = OpenMeteoWeatherResponse(
            daily: .init(
                temperature2MMean: Array(repeating: 27.4, count: 90),
                temperature2MMax: Array(repeating: 33.1, count: 90),
                temperature2MMin: Array(repeating: 20.2, count: 90),
                precipitationSum: Array(repeating: 5.6, count: 90),
                soilTemperature0cmMean: Array(repeating: 24.2, count: 90),
                relativeHumidity2MMean: Array(repeating: 68.0, count: 90),
                et0FaoEvapotranspiration: Array(repeating: 2.4, count: 90),
                shortwaveRadiationSum: Array(repeating: 18.6, count: 90),
                soilMoisture0To1cmMean: Array(repeating: 0.23, count: 90),
                windSpeed10MMean: Array(repeating: 13.2, count: 90)
            ),
            dailyUnits: .init(
                temperature2MMean: "C",
                temperature2MMax: "C",
                temperature2MMin: "C",
                precipitationSum: "mm",
                soilTemperature0cmMean: "C",
                relativeHumidity2MMean: "%",
                et0FaoEvapotranspiration: "mm",
                shortwaveRadiationSum: "MJ/m2",
                soilMoisture0To1cmMean: "m3/m3",
                windSpeed10MMean: "km/h"
            )
        )

        let air = OpenMeteoAirQualityResponse(
            hourly: .init(
                usAQI: Array(repeating: 82.0, count: 48),
                pm10: Array(repeating: 46.0, count: 48),
                pm25: Array(repeating: 21.0, count: 48),
                ozone: Array(repeating: 71.0, count: 48),
                nitrogenDioxide: nil,
                sulphurDioxide: nil,
                carbonMonoxide: nil
            ),
            hourlyUnits: .init(usAQI: nil, pm10: "ug/m3", pm25: "ug/m3", ozone: "ug/m3")
        )

        measure(metrics: [XCTClockMetric()]) {
            _ = builder.buildWeatherCards(from: weather)
            _ = builder.buildAirQualityCards(from: air)
        }
    }

    func testRunConfigurationRoundTripPerformance() throws {
        let service = SimulationRunConfigService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let document = OperationalRunConfigDocument(
            schemaVersion: 1,
            hazardType: "wildfire",
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            binaryPath: "/tmp/Cell2Fire",
            inputFolder: "/tmp/input",
            outputFolder: "/tmp/output",
            simulatorCode: "S",
            includeROS: true,
            weatherPeriodMinutes: 60,
            outputFormat: "asc",
            numberOfSimulations: 20,
            numberOfThreads: 8,
            seed: 321,
            selectedScenarioID: nil,
            scenarioName: "Stress",
            tcfdScenarioLabel: "Stress Test",
            scenarioPathway: "SSP5-8.5",
            scenarioHorizon: "5-20 years"
        )

        measure(metrics: [XCTClockMetric()]) {
            do {
                let data = try service.exportData(for: document)
                try data.write(to: tempURL, options: .atomic)
                _ = try service.importDocument(from: tempURL)
            } catch {
                XCTFail("Round-trip performance failed: \(error.localizedDescription)")
            }
        }
    }
}
