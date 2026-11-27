import Foundation
import CoreLocation

// MARK: - Open-Meteo Real-Time Environmental & Thermal Physiology Service (100% Free, Zero API Key)

struct WeatherPhysiologySnapshot: Codable, Equatable, Hashable {
    let cityName: String
    let latitude: Double
    let longitude: Double
    let temperatureC: Double
    let apparentTempC: Double
    let humidityPct: Int
    let uvIndex: Double
    let windKmh: Double
    let weatherCode: Int
    let fetchedAtEpoch: Double

    /// Heat stress tier: 0 = Optimal, 1 = Warm / Moderate thermal load, 2 = High Heat+Humidity / Cold extreme
    var heatStressLevel: Int {
        if apparentTempC >= 31.0 || (temperatureC >= 28.0 && humidityPct >= 65) || uvIndex >= 8.0 {
            return 2
        }
        if apparentTempC >= 25.5 || (temperatureC >= 23.0 && humidityPct >= 70) || temperatureC <= 3.0 || uvIndex >= 6.0 {
            return 1
        }
        return 0
    }

    /// Estimated cardiovascular HR drift (bpm) caused by ambient heat & humidity during aerobic/outdoor effort
    var estimatedHrDriftBpm: Int {
        if temperatureC < 22.0 { return 0 }
        let tempExcess = max(0.0, temperatureC - 21.0)
        let humFactor = humidityPct >= 55 ? Double(humidityPct - 50) / 18.0 : 0.0
        let raw = tempExcess * 0.65 + humFactor * 1.1
        return min(max(Int(raw.rounded()), 0), 16)
    }

    /// Extra daily hydration recommended (ml) for thermal load & sweat losses
    var extraHydrationMl: Int {
        if apparentTempC >= 32.0 { return 850 }
        if apparentTempC >= 28.0 || (temperatureC >= 26.0 && humidityPct >= 65) { return 600 }
        if apparentTempC >= 24.5 || uvIndex >= 7.0 { return 350 }
        return 0
    }

    /// Recommended protective Strain ceiling reduction (%) under high thermal stress
    var strainAdjustmentPct: Int {
        if apparentTempC >= 33.0 || (temperatureC >= 30.0 && humidityPct >= 70) { return 12 }
        if apparentTempC >= 29.0 || (temperatureC >= 27.0 && humidityPct >= 65) { return 7 }
        return 0
    }

    var conditionLabel: String {
        switch weatherCode {
        case 0: return "Despejado"
        case 1, 2: return "Poco nuboso"
        case 3: return "Nublado"
        case 45, 48: return "Niebla"
        case 51...57: return "Llovizna"
        case 61...67: return "Lluvia"
        case 71...77: return "Nieve"
        case 80...82: return "Chubascos"
        case 95...99: return "Tormenta"
        default: return "Variable"
        }
    }

    var sfSymbol: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77: return "snowflake"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    var effortImpactSummary: String {
        let tStr = String(format: "%.0f °C", locale: Locale(identifier: "es_ES"), temperatureC)
        let uvStr = String(format: "UV %.0f", locale: Locale(identifier: "es_ES"), uvIndex)
        if estimatedHrDriftBpm >= 5 {
            var bits: [String] = ["\(tStr) · \(humidityPct)% hum. · \(uvStr): el calor puede elevar tu FC +\(estimatedHrDriftBpm) ppm"]
            if extraHydrationMl > 0 { bits.append("añade +\(extraHydrationMl) ml con electrolitos") }
            if strainAdjustmentPct > 0 { bits.append("esfuerzo objetivo -\(strainAdjustmentPct)%") }
            return bits.joined(separator: "; ") + "."
        }
        if temperatureC <= 4.0 {
            return "\(tStr) · \(humidityPct)% hum.: frío intenso; alarga el calentamiento 5–8 min para estabilizar tu FC."
        }
        if uvIndex >= 6.0 {
            return "\(tStr) · \(humidityPct)% hum. · \(uvStr): radiación solar alta; prioriza sombra, protección y +\(max(extraHydrationMl, 250)) ml de agua."
        }
        return "\(tStr) · \(humidityPct)% hum. · \(uvStr): ambiente térmico favorable para rendir sin deriva cardíaca extra."
    }

    var recoveryImpactSummary: String {
        if heatStressLevel >= 2 {
            return "Estrés térmico alto (\(Int(temperatureC.rounded())) °C, \(humidityPct)% hum.): repón +\(extraHydrationMl) ml de agua y sodio para proteger tu VFC esta noche."
        }
        if heatStressLevel == 1 && temperatureC <= 4.0 {
            return "Clima frío (\(Int(temperatureC.rounded())) °C): buena termorregulación nocturna si mantienes tu habitación fresca (17–19 °C)."
        }
        if heatStressLevel == 1 {
            return "Ambiente cálido (\(Int(temperatureC.rounded())) °C, \(humidityPct)% hum.): hidrátate antes de entrenar para evitar caída de recuperación."
        }
        return "Clima neutro (\(Int(temperatureC.rounded())) °C · \(humidityPct)% hum.): sin sobrecarga térmica para tu recuperación."
    }

    var isStale: Bool {
        Date().timeIntervalSince1970 - fetchedAtEpoch > 90 * 60
    }
}

final class WeatherContextService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherContextService()

    private let session: URLSession
    @MainActor private var locationManager: CLLocationManager?
    @MainActor private var locationContinuation: CheckedContinuation<(Double, Double)?, Never>?

    override init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    /// Parses an Open-Meteo `/v1/forecast` JSON response into a typed `WeatherPhysiologySnapshot`.
    nonisolated static func parseOpenMeteoResponse(
        data: Data,
        cityName: String,
        latitude: Double,
        longitude: Double,
        nowEpoch: Double = Date().timeIntervalSince1970
    ) -> WeatherPhysiologySnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any] else {
            return nil
        }
        func num(_ key: String) -> Double? {
            if let d = current[key] as? Double { return d }
            if let i = current[key] as? Int { return Double(i) }
            if let s = current[key] as? String { return Double(s) }
            return nil
        }
        guard let temp = num("temperature_2m") else { return nil }
        let apparent = num("apparent_temperature") ?? temp
        let hum = Int((num("relative_humidity_2m") ?? 50.0).rounded())
        let uv = num("uv_index") ?? 0.0
        let wind = num("wind_speed_10m") ?? 0.0
        let code = Int((num("weather_code") ?? 0.0).rounded())
        return WeatherPhysiologySnapshot(
            cityName: cityName,
            latitude: latitude,
            longitude: longitude,
            temperatureC: (temp * 10.0).rounded() / 10.0,
            apparentTempC: (apparent * 10.0).rounded() / 10.0,
            humidityPct: min(max(hum, 0), 100),
            uvIndex: max((uv * 10.0).rounded() / 10.0, 0.0),
            windKmh: max((wind * 10.0).rounded() / 10.0, 0.0),
            weatherCode: code,
            fetchedAtEpoch: nowEpoch
        )
    }

    /// Free Open-Meteo Geocoding lookup for any user-typed city name (no API key needed).
    func geocodeCity(_ query: String) async -> (name: String, lat: Double, lon: Double)? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=es&format=json") else {
            return nil
        }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]],
                  let first = results.first,
                  let lat = first["latitude"] as? Double,
                  let lon = first["longitude"] as? Double else {
                return nil
            }
            let city = (first["name"] as? String) ?? cleaned
            return (city, lat, lon)
        } catch {
            return nil
        }
    }

    /// Fetches real-time weather from Open-Meteo for exact coordinates (100% free, zero API key).
    func fetchWeather(latitude: Double, longitude: Double, cityName: String) async -> WeatherPhysiologySnapshot? {
        let urlStr = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,relative_humidity_2m,apparent_temperature,uv_index,weather_code,wind_speed_10m&timezone=auto",
            latitude,
            longitude
        )
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return Self.parseOpenMeteoResponse(
                data: data,
                cityName: cityName,
                latitude: latitude,
                longitude: longitude
            )
        } catch {
            return nil
        }
    }

    /// Fetches weather for either a configured city name or one-shot GPS location (fallback to Madrid if neither available).
    func fetchWeatherForCityOrLocation(preferredCity: String?, requestGPSIfNeeded: Bool) async -> WeatherPhysiologySnapshot? {
        let trimmedCity = preferredCity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCity.isEmpty, let geo = await geocodeCity(trimmedCity) {
            return await fetchWeather(latitude: geo.lat, longitude: geo.lon, cityName: geo.name)
        }
        if requestGPSIfNeeded, let loc = await requestOneShotLocation() {
            let label = await reverseGeocodeCityName(for: loc) ?? "Tu ubicación"
            return await fetchWeather(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, cityName: label)
        }
        return nil
    }

    @MainActor
    private func requestOneShotLocation() async -> CLLocation? {
        if locationManager == nil {
            let mgr = CLLocationManager()
            mgr.desiredAccuracy = kCLLocationAccuracyKilometer
            mgr.delegate = self
            locationManager = mgr
        }
        guard let mgr = locationManager else { return nil }
        let status = mgr.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }
        if status == .notDetermined {
            mgr.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 1_400_000_000)
        }
        let postStatus = mgr.authorizationStatus
        guard postStatus == .authorizedWhenInUse || postStatus == .authorizedAlways else {
            return nil
        }
        if let cached = mgr.location, abs(cached.timestamp.timeIntervalSinceNow) < 900 {
            return cached
        }
        let coords: (Double, Double)? = await withCheckedContinuation { cont in
            self.locationContinuation = cont
            mgr.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let pending = self?.locationContinuation {
                    self?.locationContinuation = nil
                    pending.resume(returning: nil)
                }
            }
        }
        return coords.map { CLLocation(latitude: $0.0, longitude: $0.1) }
    }

    private func reverseGeocodeCityName(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        return await withCheckedContinuation { cont in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                let city = placemarks?.first?.locality ?? placemarks?.first?.administrativeArea
                cont.resume(returning: city)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last.map { ($0.coordinate.latitude, $0.coordinate.longitude) }
        Task { @MainActor [weak self] in
            if let pending = self?.locationContinuation {
                self?.locationContinuation = nil
                pending.resume(returning: coord)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            if let pending = self?.locationContinuation {
                self?.locationContinuation = nil
                pending.resume(returning: nil)
            }
        }
    }
}
