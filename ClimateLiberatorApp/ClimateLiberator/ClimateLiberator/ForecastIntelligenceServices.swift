import Foundation
import CoreLocation
import MapKit

struct ForecastResolvedLocation {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct ForecastBuildSupportFeeds {
    let overview: ForecastOverviewSummary?
    let providerTrust: ForecastProviderTrustFeed?
    let warningSummary: ForecastWarningSummary?
}

protocol ForecastFeedRepository {
    func loadProcessedFeed(near coordinate: CLLocationCoordinate2D, horizon: ForecastHorizon) -> ProcessedForecastFeed?
    func loadBuildSupportFeeds() -> ForecastBuildSupportFeeds
}

protocol ForecastLiveDataClient {
    func resolveLocation(query: String) async throws -> ForecastResolvedLocation
    func fetchWeatherForecast(for coordinate: CLLocationCoordinate2D,
                              horizon: ForecastHorizon) async throws -> OpenMeteoWeatherResponse
    func fetchAirQualityForecast(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoAirQualityResponse
    func fetchSeasonalForecast(for coordinate: CLLocationCoordinate2D,
                               horizon: ForecastHorizon) async throws -> OpenMeteoSeasonalResponse
}

protocol ForecastEvidenceSnapshotStore {
    func saveSnapshot(_ snapshot: ForecastEvidenceSnapshot) throws
    func loadSnapshots() -> [ForecastEvidenceSnapshot]
}

struct ForecastSnapshotContext {
    let providerID: String
    let providerLabel: String
    let sourceMode: ForecastSourceMode
    let horizon: ForecastHorizon
    let confidence: ForecastConfidence
    let generatedAt: Date?
    let validFrom: Date?
    let validTo: Date?
    let locationLabel: String
    let coordinate: CLLocationCoordinate2D
    let statusSummary: String
    let weatherCards: [ForecastMetricCard]
    let airQualityCards: [ForecastMetricCard]
}

struct ForecastSnapshotCollections {
    let executiveEligibleSnapshots: [ForecastEvidenceSnapshot]
    let disclosureEligibleSnapshots: [ForecastEvidenceSnapshot]
}

protocol ForecastEvidencePromotionManaging {
    func persistOperationalSnapshot(from context: ForecastSnapshotContext) throws -> ForecastSnapshotCollections
    func promoteSnapshot(from context: ForecastSnapshotContext, to level: ForecastPromotionLevel) throws -> ForecastSnapshotCollections
    func loadSnapshotCollections() -> ForecastSnapshotCollections
}

protocol ForecastMetricCardBuilding {
    func buildWeatherCards(from response: OpenMeteoWeatherResponse) -> [ForecastMetricCard]
    func buildWeatherCards(from response: OpenMeteoSeasonalResponse) -> [ForecastMetricCard]
    func buildAirQualityCards(from response: OpenMeteoAirQualityResponse) -> [ForecastMetricCard]
}

struct BuildForecastFeedRepository: ForecastFeedRepository {
    private let processedFeedsDirectory: URL
    private let manifestsDirectory: URL

    init(processedFeedsDirectory: URL = URL(fileURLWithPath: "/Users/afnan/Desktop/Build/environment-risk-data/data/processed", isDirectory: true),
         manifestsDirectory: URL = URL(fileURLWithPath: "/Users/afnan/Desktop/Build/environment-risk-data/data/processed/manifests", isDirectory: true)) {
        self.processedFeedsDirectory = processedFeedsDirectory
        self.manifestsDirectory = manifestsDirectory
    }

    func loadProcessedFeed(near coordinate: CLLocationCoordinate2D, horizon: ForecastHorizon) -> ProcessedForecastFeed? {
        guard FileManager.default.fileExists(atPath: processedFeedsDirectory.path) else {
            return nil
        }

        let urls = (try? FileManager.default.contentsOfDirectory(at: processedFeedsDirectory,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let feeds = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(ProcessedForecastFeed.self, from: $0) }
            .filter { $0.forecastHorizon == horizon.rawValue }

        guard !feeds.isEmpty else {
            return nil
        }

        let sorted = feeds.sorted {
            distanceInKilometers(from: coordinate, to: $0.coordinate) < distanceInKilometers(from: coordinate, to: $1.coordinate)
        }

        guard let nearest = sorted.first else {
            return nil
        }

        return distanceInKilometers(from: coordinate, to: nearest.coordinate) <= 250 ? nearest : nil
    }

    func loadBuildSupportFeeds() -> ForecastBuildSupportFeeds {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return ForecastBuildSupportFeeds(
            overview: decodeManifest("forecast_overview.json", decoder: decoder),
            providerTrust: decodeManifest("forecast_provider_trust.json", decoder: decoder),
            warningSummary: decodeManifest("forecast_warning_summary.json", decoder: decoder)
        )
    }

    private func decodeManifest<T: Decodable>(_ fileName: String, decoder: JSONDecoder) -> T? {
        let url = manifestsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func distanceInKilometers(from lhs: CLLocationCoordinate2D,
                                      to rhs: CLLocationCoordinate2D) -> Double {
        let left = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let right = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return left.distance(from: right) / 1000
    }
}

struct OpenMeteoForecastLiveClient: ForecastLiveDataClient {
    func resolveLocation(query: String) async throws -> ForecastResolvedLocation {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw NSError(domain: "ForecastIntelligence", code: 404)
        }
        let name = item.name ?? query
        return ForecastResolvedLocation(name: name, coordinate: item.location.coordinate)
    }

    func fetchWeatherForecast(for coordinate: CLLocationCoordinate2D,
                              horizon: ForecastHorizon) async throws -> OpenMeteoWeatherResponse {
        let variables = [
            "temperature_2m_mean",
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_sum",
            "soil_temperature_0cm_mean",
            "relative_humidity_2m_mean",
            "et0_fao_evapotranspiration",
            "shortwave_radiation_sum",
            "soil_moisture_0_to_1cm_mean",
            "wind_speed_10m_mean"
        ].joined(separator: ",")

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "daily", value: variables),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: horizon == .shortTerm ? "7" : "14")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: data)
    }

    func fetchAirQualityForecast(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoAirQualityResponse {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "hourly", value: "us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "5")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
    }

    func fetchSeasonalForecast(for coordinate: CLLocationCoordinate2D,
                               horizon: ForecastHorizon) async throws -> OpenMeteoSeasonalResponse {
        let variables = [
            "temperature_2m_mean",
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_sum",
            "soil_temperature_0_to_7cm_mean",
            "relative_humidity_2m_mean",
            "et0_fao_evapotranspiration",
            "shortwave_radiation_sum",
            "soil_moisture_0_to_7cm_mean",
            "wind_speed_10m_mean"
        ].joined(separator: ",")

        var components = URLComponents(string: "https://seasonal-api.open-meteo.com/v1/seasonal")!
        components.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "daily", value: variables),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: horizon == .subseasonal ? "46" : "183")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(OpenMeteoSeasonalResponse.self, from: data)
    }
}

struct FileSystemForecastEvidenceSnapshotStore: ForecastEvidenceSnapshotStore {
    private let forecastEvidenceDirectory: URL

    init(forecastEvidenceDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ClimateLiberator/_climateliberator/forecast", isDirectory: true)) {
        self.forecastEvidenceDirectory = forecastEvidenceDirectory
    }

    func saveSnapshot(_ snapshot: ForecastEvidenceSnapshot) throws {
        try FileManager.default.createDirectory(at: forecastEvidenceDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = forecastEvidenceDirectory.appendingPathComponent("\(snapshot.id).json")
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    func loadSnapshots() -> [ForecastEvidenceSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let urls = (try? FileManager.default.contentsOfDirectory(at: forecastEvidenceDirectory,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(ForecastEvidenceSnapshot.self, from: $0) }
            .sorted { $0.capturedAt > $1.capturedAt }
    }
}

struct ForecastEvidencePromotionManager: ForecastEvidencePromotionManaging {
    private let snapshotStore: ForecastEvidenceSnapshotStore

    init(snapshotStore: ForecastEvidenceSnapshotStore) {
        self.snapshotStore = snapshotStore
    }

    func persistOperationalSnapshot(from context: ForecastSnapshotContext) throws -> ForecastSnapshotCollections {
        guard let snapshot = buildSnapshot(from: context, promotionLevel: .operationsOnly) else {
            return loadSnapshotCollections()
        }
        try snapshotStore.saveSnapshot(snapshot)
        return loadSnapshotCollections()
    }

    func promoteSnapshot(from context: ForecastSnapshotContext, to level: ForecastPromotionLevel) throws -> ForecastSnapshotCollections {
        guard let snapshot = buildSnapshot(from: context, promotionLevel: level) else {
            return loadSnapshotCollections()
        }
        try snapshotStore.saveSnapshot(snapshot)
        return loadSnapshotCollections()
    }

    func loadSnapshotCollections() -> ForecastSnapshotCollections {
        let snapshots = snapshotStore.loadSnapshots()
        return ForecastSnapshotCollections(
            executiveEligibleSnapshots: snapshots.filter { $0.promotionLevel == .executiveEligible || $0.promotionLevel == .disclosureEligible },
            disclosureEligibleSnapshots: snapshots.filter { $0.promotionLevel == .disclosureEligible }
        )
    }

    private func buildSnapshot(from context: ForecastSnapshotContext,
                               promotionLevel: ForecastPromotionLevel) -> ForecastEvidenceSnapshot? {
        guard !context.weatherCards.isEmpty || !context.airQualityCards.isEmpty else { return nil }
        return ForecastEvidenceSnapshot(
            id: snapshotIdentifier(locationLabel: context.locationLabel,
                                   horizon: context.horizon,
                                   suffix: promotionLevel == .operationsOnly ? "ops" : promotionLevel.rawValue),
            capturedAt: Date(),
            providerID: context.providerID,
            providerLabel: context.providerLabel,
            sourceMode: context.sourceMode,
            horizon: context.horizon.rawValue,
            confidence: context.confidence,
            generatedAt: context.generatedAt,
            validFrom: context.validFrom,
            validTo: context.validTo,
            locationLabel: context.locationLabel,
            latitude: context.coordinate.latitude,
            longitude: context.coordinate.longitude,
            statusSummary: context.statusSummary,
            weatherMetrics: context.weatherCards.map { ForecastObservedMetric(id: $0.id, title: $0.title, value: $0.value, detail: $0.detail) },
            airQualityMetrics: context.airQualityCards.map { ForecastObservedMetric(id: $0.id, title: $0.title, value: $0.value, detail: $0.detail) },
            promotionLevel: promotionLevel,
            analystInterpretation: nil,
            linkedScenarioID: nil,
            linkedPackageRunID: nil,
            sourceHash: nil
        )
    }

    private func snapshotIdentifier(locationLabel: String,
                                    horizon: ForecastHorizon,
                                    suffix: String) -> String {
        let location = locationLabel
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "-")
        return "forecast-\(location)-\(horizon.rawValue)-\(suffix)"
    }
}

struct ForecastMetricCardBuilder: ForecastMetricCardBuilding {
    func buildWeatherCards(from response: OpenMeteoWeatherResponse) -> [ForecastMetricCard] {
        [
            summaryCard(title: "Mean Temperature", values: response.daily.temperature2MMean, unit: response.dailyUnits.temperature2MMean, aggregation: .average),
            summaryCard(title: "Max Temperature", values: response.daily.temperature2MMax, unit: response.dailyUnits.temperature2MMax, aggregation: .maximum),
            summaryCard(title: "Minimum Temperature", values: response.daily.temperature2MMin, unit: response.dailyUnits.temperature2MMin, aggregation: .minimum),
            summaryCard(title: "Precipitation", values: response.daily.precipitationSum, unit: response.dailyUnits.precipitationSum, aggregation: .total),
            summaryCard(title: "Soil Temperature", values: response.daily.soilTemperature0cmMean, unit: response.dailyUnits.soilTemperature0cmMean, aggregation: .average),
            summaryCard(title: "Relative Humidity", values: response.daily.relativeHumidity2MMean, unit: response.dailyUnits.relativeHumidity2MMean, aggregation: .average),
            summaryCard(title: "Evapotranspiration", values: response.daily.et0FaoEvapotranspiration, unit: response.dailyUnits.et0FaoEvapotranspiration, aggregation: .total),
            summaryCard(title: "Solar Radiation", values: response.daily.shortwaveRadiationSum, unit: response.dailyUnits.shortwaveRadiationSum, aggregation: .total),
            summaryCard(title: "Soil Moisture", values: response.daily.soilMoisture0To1cmMean, unit: response.dailyUnits.soilMoisture0To1cmMean, aggregation: .average),
            summaryCard(title: "Wind Speed", values: response.daily.windSpeed10MMean, unit: response.dailyUnits.windSpeed10MMean, aggregation: .average)
        ].compactMap { $0 }
    }

    func buildWeatherCards(from response: OpenMeteoSeasonalResponse) -> [ForecastMetricCard] {
        [
            summaryCard(title: "Mean Temperature", values: response.daily.temperature2MMean, unit: response.dailyUnits.temperature2MMean, aggregation: .average),
            summaryCard(title: "Max Temperature", values: response.daily.temperature2MMax, unit: response.dailyUnits.temperature2MMax, aggregation: .maximum),
            summaryCard(title: "Minimum Temperature", values: response.daily.temperature2MMin, unit: response.dailyUnits.temperature2MMin, aggregation: .minimum),
            summaryCard(title: "Precipitation", values: response.daily.precipitationSum, unit: response.dailyUnits.precipitationSum, aggregation: .total),
            summaryCard(title: "Soil Temperature", values: response.daily.soilTemperature0To7cmMean, unit: response.dailyUnits.soilTemperature0To7cmMean, aggregation: .average),
            summaryCard(title: "Relative Humidity", values: response.daily.relativeHumidity2MMean, unit: response.dailyUnits.relativeHumidity2MMean, aggregation: .average),
            summaryCard(title: "Evapotranspiration", values: response.daily.et0FaoEvapotranspiration, unit: response.dailyUnits.et0FaoEvapotranspiration, aggregation: .total),
            summaryCard(title: "Solar Radiation", values: response.daily.shortwaveRadiationSum, unit: response.dailyUnits.shortwaveRadiationSum, aggregation: .total),
            summaryCard(title: "Soil Moisture", values: response.daily.soilMoisture0To7cmMean, unit: response.dailyUnits.soilMoisture0To7cmMean, aggregation: .average),
            summaryCard(title: "Wind Speed", values: response.daily.windSpeed10MMean, unit: response.dailyUnits.windSpeed10MMean, aggregation: .average)
        ].compactMap { $0 }
    }

    func buildAirQualityCards(from response: OpenMeteoAirQualityResponse) -> [ForecastMetricCard] {
        [
            airQualityCard(title: "US AQI (next 24h max)", values: response.hourly.usAQI, unit: nil, aggregation: .maximum),
            airQualityCard(title: "PM2.5 (next 24h avg)", values: response.hourly.pm25, unit: response.hourlyUnits.pm25, aggregation: .average),
            airQualityCard(title: "PM10 (next 24h avg)", values: response.hourly.pm10, unit: response.hourlyUnits.pm10, aggregation: .average),
            airQualityCard(title: "Ozone (next 24h avg)", values: response.hourly.ozone, unit: response.hourlyUnits.ozone, aggregation: .average)
        ].compactMap { $0 }
    }

    private func summaryCard(title: String,
                             values: [Double]?,
                             unit: String?,
                             aggregation: ForecastAggregationMode) -> ForecastMetricCard? {
        guard let values, !values.isEmpty else { return nil }
        let value = aggregate(values, using: aggregation)
        return ForecastMetricCard(id: title,
                                  title: title,
                                  value: formatted(value, unit: unit),
                                  detail: aggregation.detail)
    }

    private func airQualityCard(title: String,
                                values: [Double]?,
                                unit: String?,
                                aggregation: ForecastAggregationMode) -> ForecastMetricCard? {
        guard let values, !values.isEmpty else { return nil }
        let next24h = Array(values.prefix(24))
        let value = aggregate(next24h, using: aggregation)
        return ForecastMetricCard(id: title,
                                  title: title,
                                  value: formatted(value, unit: unit),
                                  detail: "Mapped around the selected business location")
    }

    private func aggregate(_ values: [Double], using aggregation: ForecastAggregationMode) -> Double {
        switch aggregation {
        case .average:
            return values.reduce(0, +) / Double(values.count)
        case .maximum:
            return values.max() ?? 0
        case .minimum:
            return values.min() ?? 0
        case .total:
            return values.reduce(0, +)
        }
    }

    private func formatted(_ value: Double, unit: String?) -> String {
        if let unit, !unit.isEmpty {
            return String(format: "%.1f %@", value, unit)
        }
        return String(format: "%.0f", value)
    }
}

private enum ForecastAggregationMode {
    case average
    case maximum
    case minimum
    case total

    var detail: String {
        switch self {
        case .average: return "Mean of the current forecast window"
        case .maximum: return "Highest value across the current forecast window"
        case .minimum: return "Lowest value across the current forecast window"
        case .total: return "Accumulated across the current forecast window"
        }
    }
}
