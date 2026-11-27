import XCTest
@testable import Improving

/// Deterministic URLProtocol stub for testing GeminiCoachService and OpenFoodFactsService without network I/O.
private final class P3MockURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requestCount: Int = 0
    static var capturedHosts: [String] = []

    static func reset(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        self.requestCount = 0
        self.capturedHosts = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        P3MockURLProtocol.lock.lock()
        P3MockURLProtocol.requestCount += 1
        if let h = request.url?.host { P3MockURLProtocol.capturedHosts.append(h) }
        let currentHandler = P3MockURLProtocol.handler
        P3MockURLProtocol.lock.unlock()

        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (resp, data) = try currentHandler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class P3ServicesAndIntegrationTests: XCTestCase {

    private func makeMockSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [P3MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    // MARK: - 1. GeminiCoachService (429 Retry, 401 Immediate Abort, Keyless Privacy Gate)

    func testGeminiCoachService429Retry401AbortAndKeylessPrivacyGate() async throws {
        let session = makeMockSession()
        let service = GeminiCoachService(session: session)

        // A. HTTP 429 with Retry-After: 0 retries cleanly and succeeds on HTTP 200!
        var callNum = 0
        P3MockURLProtocol.reset { req in
            callNum += 1
            let url = req.url ?? URL(string: "https://generativelanguage.googleapis.com")!
            if callNum == 1 {
                let r429 = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"])!
                return (r429, Data("{\"error\":{\"message\":\"Rate limit\"}}".utf8))
            }
            let okJson = """
            {"candidates":[{"content":{"parts":[{"text":"Tu VFC de 78 ms indica recuperación óptima para entrenar fuerte hoy."}]}}]}
            """
            let r200 = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r200, Data(okJson.utf8))
        }

        let retryRes = await service.askLiveCoach(
            prompt: "¿Entreno fuerte hoy?",
            apiKey: "AIzaFakeTestKey123",
            selectedModel: "gemini-2.5-flash",
            userName: "Aitor",
            biometricContextJson: "{\"hrv_ms\":78}",
            availableHighlights: ["VFC 78 ms"],
            missingCategories: [],
            history: [],
            allowCloudAI: true,
            allowKeylessFallback: false
        )
        XCTAssertTrue(retryRes.usedLiveCloud)
        XCTAssertTrue(retryRes.text.contains("78 ms"))
        XCTAssertEqual(callNum, 2)

        // B. HTTP 401 API_KEY_INVALID aborts immediately on the first model (no 3-model fanout or pollinations leak!)
        P3MockURLProtocol.reset { req in
            let url = req.url ?? URL(string: "https://generativelanguage.googleapis.com")!
            let r401 = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (r401, Data("{\"error\":{\"message\":\"API_KEY_INVALID\"}}".utf8))
        }
        let abortRes = await service.askLiveCoach(
            prompt: "Hola",
            apiKey: "AIzaInvalidKey",
            selectedModel: "gemini-2.5-flash",
            userName: "Aitor",
            biometricContextJson: "{}",
            availableHighlights: [],
            missingCategories: [],
            history: [],
            allowCloudAI: true,
            allowKeylessFallback: false
        )
        XCTAssertFalse(abortRes.usedLiveCloud)
        XCTAssertEqual(P3MockURLProtocol.requestCount, 1)
        XCTAssertFalse(P3MockURLProtocol.capturedHosts.contains("text.pollinations.ai"))

        // C. With empty API key & allowKeylessFallback == false, ZERO external network requests are sent!
        P3MockURLProtocol.reset { req in
            let url = req.url ?? URL(string: "https://example.com")!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let offlineRes = await service.askLiveCoach(
            prompt: "Resumen",
            apiKey: "",
            selectedModel: "auto",
            userName: "Aitor",
            biometricContextJson: "{}",
            availableHighlights: [],
            missingCategories: [],
            history: [],
            allowCloudAI: true,
            allowKeylessFallback: false
        )
        XCTAssertFalse(offlineRes.usedLiveCloud)
        XCTAssertEqual(P3MockURLProtocol.requestCount, 0)
    }

    func testGeminiModelRankingWeeklyParserAndSanitizer() {
        let ranked = GeminiCoachService.rankDiscoveredModels([
            ("models/text-embedding-004", ["embedContent"]),
            ("models/gemini-2.5-flash-lite", ["generateContent"]),
            ("models/gemini-3.1-flash-lite", ["generateContent"]),
            ("models/gemma-3-27b", ["generateContent"]),
            ("models/gemini-2.5-flash-native-audio", ["generateContent"]),
            ("models/gemini-3-flash", ["generateContent"])
        ])
        XCTAssertEqual(ranked.first, "gemini-3.1-flash-lite")
        XCTAssertTrue(ranked.contains("gemini-3-flash"))
        XCTAssertFalse(ranked.contains("gemma-3-27b"))
        XCTAssertFalse(ranked.contains("gemini-2.5-flash-native-audio"))

        let weeklyJson = """
        {"headline":"Semana en ascenso","takeaways":["VFC estable toda la semana","Mantener 8h de sueño"]}
        """
        let parsed = GeminiCoachService.parseWeeklyReviewJson(
            weeklyJson,
            weekKey: "2026-W48",
            generatedAt: "10:00",
            modelUsed: "gemini-3-flash",
            isLiveAI: true
        )
        XCTAssertEqual(parsed?.headline, "Semana en ascenso")
        XCTAssertEqual(parsed?.takeaways.first, "VFC estable toda la semana")

        let sanitized = GeminiCoachService.sanitizeDirectHumanText("Opinión IA: **Buen ritmo** (sin fatiga)")
        XCTAssertFalse(sanitized.contains("**"))
        XCTAssertFalse(sanitized.contains("("))
        XCTAssertFalse(sanitized.lowercased().hasPrefix("opinión"))
    }

    // MARK: - 2. OpenFoodFactsService (503 Retry, JSON Decode & Cache Hit)

    func testOpenFoodFactsRetryDecodeAndMemoryCache() async {
        let session = makeMockSession()
        let barcode = "8412345999001"
        var offCalls = 0
        P3MockURLProtocol.reset { req in
            offCalls += 1
            let url = req.url ?? URL(string: "https://world.openfoodfacts.org")!
            if offCalls == 1 {
                return (HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
            }
            let payload = """
            {
              "status": 1,
              "product": {
                "code": "\(barcode)",
                "product_name_es": "Yogur Griego Natural",
                "brands": "Improving Dairy",
                "serving_quantity": 125,
                "nutriscore_grade": "a",
                "nova_group": 1,
                "nutriments": {
                  "energy-kcal_100g": 95,
                  "proteins_100g": 9.5,
                  "carbohydrates_100g": 3.8,
                  "fat_100g": 4.5,
                  "sugars_100g": 3.5,
                  "salt_100g": 0.12,
                  "fiber_100g": 0.0,
                  "calcium_100g": 0.14
                }
              }
            }
            """
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(payload.utf8))
        }

        let first = await OpenFoodFactsService.lookupProduct(barcode: barcode, session: session)
        XCTAssertNil(first.errorMessage)
        XCTAssertEqual(first.product?.productName, "Yogur Griego Natural")
        XCTAssertEqual(offCalls, 2)

        let meal = first.product?.toMealEstimate(grams: 200)
        XCTAssertEqual(meal?.kcal, 190)
        XCTAssertEqual(meal?.proteinG, 19)

        // Second lookup must hit memory cache with ZERO extra HTTP requests!
        let cached = await OpenFoodFactsService.lookupProduct(barcode: barcode, session: session)
        XCTAssertEqual(cached.product?.productName, "Yogur Griego Natural")
        XCTAssertEqual(offCalls, 2)
    }

    // MARK: - 3. WhoopExportImporter Real CSV Ingestion

    func testWhoopExportImporterParsesCyclesSleepsAndWorkouts() {
        let cyclesCsv = """
        Cycle start time,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Day Strain,Blood oxygen %,Respiratory rate (rpm),Sleep performance %
        2026-11-20 23:10:00,84,49,81.5,14.2,98.2,14.3,91
        """
        let sleepsCsv = """
        Wake onset,Asleep duration (min),In bed duration (min),Deep (SWS) duration (min),REM duration (min),Sleep performance %
        2026-11-20 07:20:00,468,495,94,108,91
        """
        let workoutsCsv = """
        Workout start time,Activity name,Duration (min),Average HR (bpm),Activity Strain,Energy burned (cal)
        2026-11-20 18:00:00,Running,45,158,13.6,540
        """

        let res = WhoopExportImporter.parseNamedCsvs([
            ("physiological_cycles.csv", Data(cyclesCsv.utf8)),
            ("sleeps.csv", Data(sleepsCsv.utf8)),
            ("workouts.csv", Data(workoutsCsv.utf8))
        ])

        XCTAssertNil(res.errorMessage)
        XCTAssertEqual(res.days.count, 1)
        let day = res.days["2026-11-20"]
        XCTAssertEqual(day?.recoveryPct, 84)
        XCTAssertEqual(day?.restingHrBpm, 49)
        XCTAssertEqual(day?.hrvMs, 81.5)
        XCTAssertEqual(day?.hrvMethodLabel, "RMSSD · WHOOP")
        XCTAssertEqual(day?.asleepMinutes, 468)
        XCTAssertEqual(day?.deepMinutes, 94)
        XCTAssertEqual(day?.remMinutes, 108)
        XCTAssertEqual(day?.workouts.count, 1)
        XCTAssertEqual(day?.workouts.first?.title, "Running")
    }

    // MARK: - 4. ZipArchiveReader Stored Roundtrip + ZIP-Bomb Rejection

    private func buildSyntheticStoredZip(entryName: String, payload: Data, fakeUncompressedSize: UInt32? = nil) -> Data {
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        let nameBytes = [UInt8](entryName.utf8)
        let compSize = UInt32(payload.count)
        let uncompSize = fakeUncompressedSize ?? compSize

        var out: [UInt8] = []
        // Local file header (0x04034b50)
        out += [0x50, 0x4B, 0x03, 0x04]
        out += le16(20) // version needed
        out += le16(0)  // flags
        out += le16(0)  // method 0 = stored
        out += le16(0) + le16(0) // time/date
        out += le32(0)  // crc32 (unused by reader)
        out += le32(compSize)
        out += le32(uncompSize)
        out += le16(UInt16(nameBytes.count))
        out += le16(0)  // extra len
        out += nameBytes
        out += [UInt8](payload)

        let cdOffset = UInt32(out.count)
        // Central directory header (0x02014b50)
        out += [0x50, 0x4B, 0x01, 0x02]
        out += le16(20) + le16(20)
        out += le16(0) + le16(0) // flags + method stored
        out += le16(0) + le16(0) // time/date
        out += le32(0) // crc
        out += le32(compSize)
        out += le32(uncompSize)
        out += le16(UInt16(nameBytes.count))
        out += le16(0) + le16(0) // extra + comment
        out += le16(0) + le16(0) // disk + internal attrs
        out += le32(0) // external attrs
        out += le32(0) // local header offset
        out += nameBytes

        let cdSize = UInt32(out.count) - cdOffset
        // End of central directory (0x06054b50)
        out += [0x50, 0x4B, 0x05, 0x06]
        out += le16(0) + le16(0)
        out += le16(1) + le16(1)
        out += le32(cdSize)
        out += le32(cdOffset)
        out += le16(0)
        return Data(out)
    }

    func testZipArchiveReaderRoundTripAndZipBombProtection() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("improving_zip_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // A. Valid stored ZIP round-trip
        let expectedXml = Data("<HealthData locale=\"es_ES\"></HealthData>".utf8)
        let validZipUrl = tmpDir.appendingPathComponent("valid.zip")
        try buildSyntheticStoredZip(entryName: "apple_health_export/export.xml", payload: expectedXml).write(to: validZipUrl)

        let entries = try ZipArchiveReader.listEntries(in: validZipUrl)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "apple_health_export/export.xml")
        let extracted = try ZipArchiveReader.readEntryData(try XCTUnwrap(entries.first), from: validZipUrl)
        XCTAssertEqual(extracted, expectedXml)

        // B. Oversized header (> 1.5 GB cap) triggers ZipError.archiveTooLarge instead of OOM!
        let bombZipUrl = tmpDir.appendingPathComponent("bomb.zip")
        try buildSyntheticStoredZip(entryName: "bomb.xml", payload: Data("abc".utf8), fakeUncompressedSize: 2_000_000_000).write(to: bombZipUrl)
        let bombEntries = try ZipArchiveReader.listEntries(in: bombZipUrl)
        XCTAssertThrowsError(try ZipArchiveReader.readEntryData(try XCTUnwrap(bombEntries.first), from: bombZipUrl)) { err in
            guard case ZipArchiveReader.ZipError.archiveTooLarge = err else {
                XCTFail("Expected ZipError.archiveTooLarge, got \(err)")
                return
            }
        }
    }

    // MARK: - 5. Widget Snapshot, Notification Plan & P3 Regressions

    func testWidgetSnapshotNotificationsAndP3Regressions() throws {
        // Widget snapshot Codable roundtrip
        let snap = ImprovingWidgetSnapshot.placeholder
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(ImprovingWidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.dateIso, snap.dateIso)
        XCTAssertEqual(decoded.recoveryPct, snap.recoveryPct)
        XCTAssertFalse(decoded.isEmpty)

        // SmartNotificationSettings legacy JSON decode defaults cleanly
        let legacyNotif = try JSONDecoder().decode(SmartNotificationSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacyNotif.journalReminderHour, 22)
        XCTAssertEqual(legacyNotif.smartAlarmHour, 7)

        let sleepPlan = LocalNotificationManager.computeSleepNotificationPlan(
            wakeHour: 6, wakeMinute: 30, sleepNeedMinutes: 480, leadMinutes: 30
        )
        XCTAssertEqual(sleepPlan.bedtimeLabel, "22:30")
        XCTAssertEqual(sleepPlan.notifyLabel, "22:00")

        // P3 #103: nonBinary VO2 max & HRR norms sit strictly between female and male norms + observedPeakHr override
        var maleP = UserPhysiologyProfile(ageYears: 30, sex: .male, weightKg: 75, heightCm: 178)
        maleP.birthDateIso = nil
        var femaleP = UserPhysiologyProfile(ageYears: 30, sex: .female, weightKg: 75, heightCm: 178)
        femaleP.birthDateIso = nil
        var nbP = UserPhysiologyProfile(ageYears: 30, sex: .nonBinary, weightKg: 75, heightCm: 178)
        nbP.birthDateIso = nil

        let mNorm = WhoopPhysiologyEngine.computePersonalizedNorms(profile: maleP)
        let fNorm = WhoopPhysiologyEngine.computePersonalizedNorms(profile: femaleP)
        let nbNorm = WhoopPhysiologyEngine.computePersonalizedNorms(profile: nbP, observedPeakHrBpm: 204)
        XCTAssertGreaterThan(nbNorm.vo2GoodThreshold, fNorm.vo2GoodThreshold)
        XCTAssertLessThan(nbNorm.vo2GoodThreshold, mNorm.vo2GoodThreshold)
        XCTAssertGreaterThan(nbNorm.vo2ExcellentThreshold, fNorm.vo2ExcellentThreshold)
        XCTAssertLessThan(nbNorm.vo2ExcellentThreshold, mNorm.vo2ExcellentThreshold)
        XCTAssertEqual(nbNorm.maxHrBpm, 204)

        // P3 #104: HomeLayoutPreferences.isCompactMode backward-compatible Codable
        let legacyLayout = try JSONDecoder().decode(HomeLayoutPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacyLayout.isCompactMode)
        var compactLayout = HomeLayoutPreferences()
        compactLayout.isCompactMode = true
        let layoutRT = try JSONDecoder().decode(HomeLayoutPreferences.self, from: try JSONEncoder().encode(compactLayout))
        XCTAssertTrue(layoutRT.isCompactMode)

        // P3 #89: Unified Spanish FitnessRangeControlBar options
        XCTAssertEqual(FitnessRangeControlBar.options, ["7 d", "30 d", "3 M", "1 A", "Año"])
        XCTAssertEqual(FitnessRangeControlBar.spanDays(for: "7 d"), 7)
        XCTAssertGreaterThanOrEqual(FitnessRangeControlBar.spanDays(for: "Año"), 7)

        // P3 #102: computeMultiPeriodTrendRows does NOT linearly fabricate daily points across a 50-day missing gap!
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date())
        let dOld = cal.date(byAdding: .day, value: -60, to: anchor)!
        let dNow = anchor
        let hist: [String: RealBiometricDaySummary] = [
            AppFormatters.isoDayString(from: dOld): RealBiometricDaySummary(dateIso: AppFormatters.isoDayString(from: dOld), vo2MaxMlKgMin: 44.0),
            AppFormatters.isoDayString(from: dNow): RealBiometricDaySummary(dateIso: AppFormatters.isoDayString(from: dNow), vo2MaxMlKgMin: 50.0)
        ]
        let trends = WhoopPhysiologyEngine.computeMultiPeriodTrendRows(history: hist, anchorDate: anchor, extractor: \.vo2MaxMlKgMin)
        let row90 = trends.first(where: { $0.periodDays == 90 })
        // With 60-day gap NOT interpolated, rolling7 only has ~8 populated days instead of 61 fabricated days!
        XCTAssertLessThan(row90?.sparklinePoints.count ?? 99, 20)

        // P3 #114: L10n Spanish defaults
        XCTAssertEqual(L10n.coachTitle, "Coach IA")
        XCTAssertEqual(L10n.basics, "Fundamentos")
        XCTAssertEqual(L10n.yearToDate, "Año")
    }

    // MARK: - 6. WHOOP Parity Suite (Next-Day Lag, Naps, Sleep Consistency, 2+ Vitals Alert, Pace of Aging & Strength RPE)

    @MainActor
    func testWhoopParityFeaturesEndToEnd() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("improving_whoop_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let storeUrl = tmpDir.appendingPathComponent("store.json")
        let store = ImprovingStore(persistenceURL: storeUrl)
        store.hasImportedOrPairedRealData = true

        // 1. Sleep Consistency % (tight schedule > 90%, chaotic schedule < 60%)
        let consistent = WhoopPhysiologyEngine.computeSleepConsistencyPercent(sessions: [
            (23 * 60 + 10, 7 * 60 + 15),
            (23 * 60 + 20, 7 * 60 + 20),
            (23 * 60 + 15, 7 * 60 + 10),
            (23 * 60 + 05, 7 * 60 + 15),
        ])
        let erratic = WhoopPhysiologyEngine.computeSleepConsistencyPercent(sessions: [
            (22 * 60, 6 * 60),
            (1 * 60 + 30, 10 * 60),
            (23 * 60, 7 * 60),
            (2 * 60, 11 * 60),
        ])
        XCTAssertGreaterThanOrEqual(consistent ?? 0, 90)
        XCTAssertLessThan(erratic ?? 100, 60)

        // 2. Nap Credit + WHOOP Sleep Coach 3-Mode Planner (100% / 85% / 70%) + Persistence
        let todayIso = store.isoFormatter.string(from: Date())
        store.setSleepGoalPct(100)
        let fullNeed = store.tonightSleepNeedBreakdown.totalMin
        store.logNap(minutes: 60, for: todayIso)
        let afterNapNeed = store.tonightSleepNeedBreakdown.totalMin
        XCTAssertEqual(store.napCreditMinutes(for: todayIso), 51) // 60 * 0.85 = 51 min credit
        XCTAssertLessThan(afterNapNeed, fullNeed)
        store.setSleepGoalPct(70)
        let getByNeed = store.tonightSleepNeedBreakdown.totalMin
        XCTAssertLessThan(getByNeed, afterNapNeed)
        store.flushPersistenceNow()
        let reloaded = ImprovingStore(persistenceURL: storeUrl)
        XCTAssertEqual(reloaded.napMinutes(for: todayIso), 60)
        XCTAssertEqual(reloaded.sleepGoalPct, 70)

        // 3. 2+ Unhealthy Overnight Vitals -> Critical Health Monitor Alert + Automatic Effort Cap Reduction!
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for back in 1...14 {
            let dt = cal.date(byAdding: .day, value: -back, to: today)!
            let iso = store.isoFormatter.string(from: dt)
            store.realHistory[iso] = RealBiometricDaySummary(
                dateIso: iso,
                restingHrBpm: 50.0,
                hrvMs: 78.0,
                respRateRpm: 14.0,
                wristTempAbsoluteC: 35.8,
                spo2Percent: 98.0,
                strainPct: 55,
                recoveryPct: 75
            )
        }
        // Normal day first
        store.realHistory[todayIso] = RealBiometricDaySummary(
            dateIso: todayIso,
            restingHrBpm: 50.0,
            hrvMs: 78.0,
            respRateRpm: 14.0,
            wristTempAbsoluteC: 35.8,
            spo2Percent: 98.0,
            recoveryPct: 75
        )
        store.dataRevision += 1
        let normalRange = store.personalizedEffortTarget(for: todayIso).range
        XCTAssertFalse(store.healthMonitorAlert(for: todayIso).isCritical)

        // Now simulate illness onset: HRV drops sharply, RHR spikes, Wrist Temp elevates!
        store.realHistory[todayIso] = RealBiometricDaySummary(
            dateIso: todayIso,
            restingHrBpm: 64.0,
            hrvMs: 36.0,
            respRateRpm: 17.5,
            wristTempAbsoluteC: 37.2,
            spo2Percent: 98.0,
            recoveryPct: 75
        )
        store.dataRevision += 1
        let sickAlert = store.healthMonitorAlert(for: todayIso)
        let sickRange = store.personalizedEffortTarget(for: todayIso).range
        XCTAssertTrue(sickAlert.isCritical)
        XCTAssertGreaterThanOrEqual(sickAlert.count, 3)
        XCTAssertLessThan(sickRange.upperBound, normalRange.upperBound - 0.12)

        // 4. WHOOP Healthspan Pace of Aging (improving bio age -> < 1.0x; worsening -> > 1.0x)
        let prof = UserPhysiologyProfile(ageYears: 30, sex: .male, weightKg: 74, heightCm: 178)
        let youngEval = WhoopPhysiologyEngine.computeBiologicalAge(profile: prof, meanRhr: 47, meanHrv: 92, meanSleepHours: 8.0, meanSteps: 11500, vo2Max: 56)
        let olderPrior = WhoopPhysiologyEngine.computeBiologicalAge(profile: prof, meanRhr: 58, meanHrv: 58, meanSleepHours: 6.8, meanSteps: 6000, vo2Max: 44)
        let improvingPace = WhoopPhysiologyEngine.computePaceOfAging(currentEval: youngEval, priorEval: olderPrior)
        XCTAssertLessThan(improvingPace.multiplier, 0.9)
        let worseningPace = WhoopPhysiologyEngine.computePaceOfAging(currentEval: olderPrior, priorEval: youngEval)
        XCTAssertGreaterThan(worseningPace.multiplier, 1.1)

        // 5. Strength Trainer RPE (RPE 9 produces meaningfully higher muscular strain than RPE 3 for identical tonnage!)
        let lowRpe = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: 45, kcal: 240, avgHrBpm: 0, totalSets: 12, totalVolumeKg: 6000, rpe: 3)
        let highRpe = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: 45, kcal: 240, avgHrBpm: 0, totalSets: 12, totalVolumeKg: 6000, rpe: 9)
        XCTAssertGreaterThanOrEqual(highRpe.strainPct, lowRpe.strainPct + 8)
        XCTAssertGreaterThan(highRpe.strain21, lowRpe.strain21 + 1.0)
        let sampleSets = [
            StrengthLoggedSet(id: "s1", dateIso: todayIso, exercise: "Sentadilla", reps: 8, weightKg: 100, primaryMuscles: [.cuadriceps], secondaryMuscles: [.gluteos], completed: true)
        ]
        store.logCompletedStrengthSession(title: "Pierna Fuerza", durationMin: 50, kcal: 300, sets: sampleSets, rpe: 9)
        XCTAssertEqual(store.realHistory[todayIso]?.workouts.first?.rpe, 9)
    }

    // MARK: - 7. Bevel & WHOOP Supremacy Suite (Apartado 1 [1,2,4,5,6,7,8] + Apartado 2 [1,2,3])

    @MainActor
    func testBevelAndWhoopSupremacySuiteEndToEnd() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("improving_supremacy_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let storeUrl = tmpDir.appendingPathComponent("store.json")
        let store = ImprovingStore(persistenceURL: storeUrl)
        store.hasImportedOrPairedRealData = true
        let todayIso = store.isoFormatter.string(from: Date())
        let cal = Calendar.current
        let yesterdayIso = store.isoFormatter.string(from: cal.date(byAdding: .day, value: -1, to: Date())!)

        // 1. Strength Builder Catalog, Epley 1RM, PRs & Progressive Overload + Auto-Deload scaling
        XCTAssertGreaterThanOrEqual(StrengthCatalogExercise.all.count, 30)
        let benchSet = StrengthLoggedSet(
            id: "b1",
            dateIso: yesterdayIso,
            exercise: "Press banca con barra",
            reps: 8,
            weightKg: 80.0,
            primaryMuscles: [.pectorales],
            secondaryMuscles: [.triceps, .hombros],
            completed: true,
            setKind: .effective,
            rpe: 8,
            rir: 2
        )
        store.strengthLogs = [benchSet]
        XCTAssertEqual(benchSet.estimatedOneRepMaxKg, 80.0 * (1.0 + 8.0 / 30.0), accuracy: 0.05)

        let greenSnap = WhoopPhysiologyEngine.computeExercisePerformanceSnapshot(
            exerciseName: "Press banca con barra",
            logs: store.strengthLogs,
            recoveryPct: 82,
            deloadActive: false
        )
        XCTAssertEqual(greenSnap.suggestedWeightKg, 82.5, accuracy: 0.01)

        let deloadSnap = WhoopPhysiologyEngine.computeExercisePerformanceSnapshot(
            exerciseName: "Press banca con barra",
            logs: store.strengthLogs,
            recoveryPct: 82,
            deloadActive: true
        )
        XCTAssertEqual(deloadSnap.suggestedWeightKg, 67.5, accuracy: 0.01) // 80 * 0.85 rounded to 2.5

        // 2. Quantified Journal, Auto-Sync from Nutrition & 5h Caffeine Half-Life + Fasting Window
        let morningMeal = NutritionMealItem(id: "m1", title: "Huevos y avena", timeLabel: "09:00", kcal: 520, proteinG: 36, carbsG: 50, fatG: 18, qualityScore: 90, fiberG: 8.5)
        let lateCoffee = NutritionMealItem(id: "m2", title: "Doble espresso tarde", timeLabel: "18:00", kcal: 15, proteinG: 0, carbsG: 2, fatG: 0, qualityScore: 80, caffeineMg: 200)
        let lateDinner = NutritionMealItem(id: "m3", title: "Salmón con arroz", timeLabel: "21:30", kcal: 680, proteinG: 48, carbsG: 65, fatG: 22, qualityScore: 88, fiberG: 6.0, omega3G: 2.1)
        store.saveMeal(morningMeal, for: todayIso)
        store.saveMeal(lateCoffee, for: todayIso)
        store.saveMeal(lateDinner, for: todayIso)

        // Auto-synced into Diario without double entry!
        XCTAssertEqual(store.journalCheckinsByDate[todayIso]?["caffeine"], .yes)
        XCTAssertEqual(store.journalQuantitiesByDate[todayIso]?["caffeine"] ?? 0, 200.0, accuracy: 0.1)
        XCTAssertEqual(store.journalEventTime(habitId: "caffeine", for: todayIso), "18:00")
        XCTAssertEqual(store.journalCheckinsByDate[todayIso]?["late_meal"], .yes)

        let timing = WhoopPhysiologyEngine.computeCaffeineAndMealTiming(meals: store.mealsByDate[todayIso] ?? [], bedtimeMinutesOfDay: 23 * 60)
        XCTAssertEqual(timing.estimatedCaffeineAtBedtimeMg, 100.0, accuracy: 0.5) // 5h elapsed (18:00 -> 23:00) = exactly 1 half-life (200 * 0.5 = 100 mg)
        XCTAssertFalse(timing.caffeineClearForSleep)
        XCTAssertEqual(timing.eatingWindowHours ?? 0, 12.5, accuracy: 0.15)
        XCTAssertEqual(timing.fastingHours ?? 0, 11.5, accuracy: 0.15)
        XCTAssertEqual(timing.hoursFromLastMealToBedtime ?? 0, 1.5, accuracy: 0.15)

        // 3. Zero-Friction Nutrition: Repeat Yesterday, Multi-Ingredient Recipes & Quantified Micronutrients
        store.mealsByDate[yesterdayIso] = [morningMeal]
        store.mealsByDate[todayIso] = []
        let copied = store.repeatYesterdayMeals(for: todayIso)
        XCTAssertEqual(copied, 1)
        XCTAssertEqual(store.mealsByDate[todayIso]?.count, 1)

        let recipe = NutritionRecipeTemplate(
            id: "rec_1",
            title: "Bowl Longevidad",
            emoji: "🥗",
            servings: 2,
            ingredients: [
                NutritionRecipeIngredient(id: "ri1", name: "Pollo", grams: 300, kcal: 500, proteinG: 90, carbsG: 0, fatG: 12, fiberG: 0),
                NutritionRecipeIngredient(id: "ri2", name: "Quinoa", grams: 200, kcal: 300, proteinG: 10, carbsG: 54, fatG: 4, fiberG: 7)
            ]
        )
        store.saveNutritionRecipe(recipe)
        store.logRecipeServing(recipe, servingsCount: 1.0, for: todayIso)
        XCTAssertEqual(recipe.kcalPerServing, 400)
        XCTAssertEqual(recipe.proteinPerServing, 50)
        XCTAssertEqual(store.dailyMicronutrientsSnapshot.count, 8)

        // 4. Coach Memory, Global Goal Modes & Morning Briefing
        store.addCoachMemoryNote("Preparo media maratón en noviembre")
        XCTAssertEqual(store.coachMemoryNotes.count, 1)
        store.setGlobalGoalMode(.definicion)
        let defKcal = store.effectiveNutritionGoals.kcal
        store.setGlobalGoalMode(.volumen)
        let volKcal = store.effectiveNutritionGoals.kcal
        XCTAssertGreaterThan(volKcal, defKcal + 350)
        XCTAssertEqual(store.morningBriefingSnapshot.goalMode, .volumen)

        // 5. 9-Pillar Healthspan, Circadian Alignment, Menstrual Cycle Luteal Calibration & Overtraining Auto-Deload
        let prof = UserPhysiologyProfile(ageYears: 32, sex: .female, weightKg: 62, heightCm: 168)
        let bio9 = WhoopPhysiologyEngine.computeBiologicalAge(
            profile: prof,
            meanRhr: 50,
            meanHrv: 82,
            meanSleepHours: 7.9,
            meanSteps: 10500,
            vo2Max: 49,
            sleepConsistencyPct: 90,
            weeklyZone1To3Min: 180,
            weeklyZone4To5Min: 35,
            weeklyStrengthMin: 95
        )
        XCTAssertTrue(bio9.hasSleepConsistency && bio9.hasWeeklyZones && bio9.hasWeeklyStrength)
        XCTAssertLessThan(bio9.sleepConsistencyDelta, 0)
        XCTAssertLessThan(bio9.weeklyZonesDelta, 0)
        XCTAssertLessThan(bio9.weeklyStrengthDelta, 0)

        // Menstrual Cycle Luteal Phase (22 days after period start)
        let lutealStart = cal.date(byAdding: .day, value: -21, to: Date())!
        let cycleCfg = CycleTrackingSettings(
            isEnabled: true,
            lastPeriodStartIso: store.isoFormatter.string(from: lutealStart),
            cycleLengthDays: 28,
            periodDurationDays: 5
        )
        let cycleSnap = WhoopPhysiologyEngine.computeCyclePhase(settings: cycleCfg, referenceDate: Date())
        XCTAssertEqual(cycleSnap?.phase, .luteal)
        XCTAssertEqual(cycleSnap?.isLutealCalibrationActive, true)

        // Overtraining detector & Clinical PDF/CSV Export
        let overDays = [
            RealBiometricDaySummary(dateIso: "2026-11-23", hrvMs: 74, sleepDebtMinutes: 85, workouts: [EffortEventItem(id: "w1", title: "HIIT", timeRange: "18:00", durationMin: 50, avgHrBpm: 165, strainScore: 16, strainPct: 80, categoryLabel: "Cardio", kcal: 550, rpe: 9)]),
            RealBiometricDaySummary(dateIso: "2026-11-24", hrvMs: 65, sleepDebtMinutes: 90, workouts: [EffortEventItem(id: "w2", title: "Fuerza", timeRange: "18:00", durationMin: 60, avgHrBpm: 145, strainScore: 15, strainPct: 75, categoryLabel: "Fuerza", kcal: 420, rpe: 9)]),
            RealBiometricDaySummary(dateIso: "2026-11-25", hrvMs: 56, sleepDebtMinutes: 95)
        ]
        let deloadAssess = WhoopPhysiologyEngine.computeOvertrainingDeloadAssessment(recentDays: overDays, acwr: 1.42, deloadModeActive: false)
        XCTAssertEqual(deloadAssess.riskLevel, 2)
        XCTAssertEqual(deloadAssess.deloadWeightFactor, 0.85, accuracy: 0.01)

        let pdfUrl = try ClinicalReportExporter.generateClinicalPDF(store: store, periodDays: 30)
        let pdfData = try Data(contentsOf: pdfUrl)
        XCTAssertGreaterThan(pdfData.count, 1024)
        let csvUrl = try ClinicalReportExporter.generateBiometricCSV(store: store, periodDays: 30)
        let csvStr = try String(contentsOf: csvUrl, encoding: .utf8)
        XCTAssertTrue(csvStr.contains("Fecha,Recuperacion_Pct"))

        // Persistence round-trip for all new fields
        store.updateCycleTrackingSettings(cycleCfg)
        store.toggleAutoDeloadMode(true)
        store.flushPersistenceNow()
        let reloaded = ImprovingStore(persistenceURL: storeUrl)
        XCTAssertEqual(reloaded.coachMemoryNotes, ["Preparo media maratón en noviembre"])
        XCTAssertEqual(reloaded.globalGoalMode, .volumen)
        XCTAssertEqual(reloaded.nutritionRecipes.count, 1)
        XCTAssertTrue(reloaded.cycleTrackingSettings.isEnabled)
        XCTAssertTrue(reloaded.autoDeloadModeActive)

        // 6. Caffeine Pharmacokinetic Window (T½ 5.5 h, 20 mg sleep threshold) & Goal Mode Emojis
        XCTAssertEqual(GlobalGoalMode.allCases.map(\.emoji).count, 5)
        XCTAssertEqual(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: 28), 160)   // 2 h 40 min
        XCTAssertEqual(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: 34), 253)   // 4 h 13 min
        XCTAssertEqual(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: 46), 397)   // 6 h 37 min
        XCTAssertEqual(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: 80), 660)   // 11 h
        XCTAssertEqual(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: 160), 990)  // 16 h 30 min
        XCTAssertEqual(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: 200), 1096) // 18 h 16 min

        store.mealsByDate[todayIso] = []
        store.logQuickCaffeineDrink(title: "Espresso (30 ml)", mg: 65, emoji: "☕", timeLabel: "10:00", for: todayIso)
        let cSnap = WhoopPhysiologyEngine.computeCaffeineWindowTimeline(
            meals: store.mealsByDate[todayIso] ?? [],
            wakeMinuteOfDay: 7 * 60 + 30,
            bedtimeMinuteOfDay: 23 * 60 + 30,
            nowMinuteOfDay: 11 * 60
        )
        XCTAssertEqual(cSnap.phase, .optimal)
        XCTAssertGreaterThan(cSnap.currentBodyMg, 50.0)
        XCTAssertLessThanOrEqual(cSnap.residualAtBedtimeMg, 20.0)
        XCTAssertTrue(WhoopPhysiologyEngine.isDrinkSafeForSleepNow(drinkMg: 28, snapshot: cSnap))
        XCTAssertFalse(WhoopPhysiologyEngine.isDrinkSafeForSleepNow(drinkMg: 160, snapshot: cSnap))
        XCTAssertEqual(cSnap.curvePoints.count, 65)

        // 7. Polish round checks: 0-kcal caffeine drinks do not pollute nutrition score/mealCount,
        // deleting a meal clears auto-synced Diario caffeine, and custom goal overrides can be reset cleanly.
        XCTAssertNil(store.nutritionScore(for: todayIso))
        let cafOnlyTotals = store.nutritionDayTotals(for: todayIso)
        XCTAssertEqual(cafOnlyTotals.mealCount, 0)
        XCTAssertEqual(cafOnlyTotals.kcal, 0)
        XCTAssertEqual(store.journalCheckinsByDate[todayIso]?["caffeine"], .yes)
        XCTAssertEqual(store.journalQuantitiesByDate[todayIso]?["caffeine"] ?? 0, 65.0, accuracy: 0.1)

        if let espId = store.mealsByDate[todayIso]?.first?.id {
            store.deleteMeal(id: espId, for: todayIso)
        }
        XCTAssertNil(store.journalCheckinsByDate[todayIso]?["caffeine"])
        XCTAssertNil(store.journalQuantitiesByDate[todayIso]?["caffeine"])

        XCTAssertFalse(store.hasCustomNutritionGoalOverrides)
        store.updateNutritionGoals(CustomNutritionGoals(caloriesKcal: 1850))
        XCTAssertTrue(store.hasCustomNutritionGoalOverrides)
        XCTAssertEqual(store.effectiveNutritionGoals.kcal, 1850)
        store.clearCustomNutritionGoals()
        XCTAssertFalse(store.hasCustomNutritionGoalOverrides)
        XCTAssertEqual(store.effectiveNutritionGoals.kcal, volKcal)
    }

    @MainActor
    func testWeatherCarbCyclingLongTermJournalAgenticPlanningAndCrossCausality() throws {
        let storeUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("improving_supremacy_v2_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeUrl) }
        let store = ImprovingStore(persistenceURL: storeUrl)
        store.hasImportedOrPairedRealData = true
        let todayIso = store.selectedDateIso

        // 1. Open-Meteo Weather Physiology Parsing + Hydration & Effort Target Adjustment
        let openMeteoJson = """
        {
          "current": {
            "temperature_2m": 31.5,
            "relative_humidity_2m": 74,
            "apparent_temperature": 35.2,
            "uv_index": 8.4,
            "wind_speed_10m": 9.5,
            "weather_code": 0
          }
        }
        """
        let baseHydration = store.effectiveHydrationGoalMl
        let baseEffortHigh = store.optimalEffortRange.upperBound
        let wSnap = try XCTUnwrap(
            WeatherContextService.parseOpenMeteoResponse(
                data: try XCTUnwrap(openMeteoJson.data(using: .utf8)),
                cityName: "Valencia",
                latitude: 39.4699,
                longitude: -0.3763
            )
        )
        XCTAssertEqual(wSnap.heatStressLevel, 2)
        XCTAssertGreaterThanOrEqual(wSnap.estimatedHrDriftBpm, 6)
        XCTAssertGreaterThanOrEqual(wSnap.extraHydrationMl, 600)
        XCTAssertGreaterThanOrEqual(wSnap.strainAdjustmentPct, 7)
        store.weatherCityName = "Valencia"
        store.weatherSnapshot = wSnap
        store.dataRevision += 1
        XCTAssertGreaterThanOrEqual(store.effectiveHydrationGoalMl, baseHydration + 600.0)
        XCTAssertLessThan(store.optimalEffortRange.upperBound, baseEffortHigh)

        // 2. Dynamic Strain-Based Carb Cycling (High Load >= 14 vs Rest Day < 7)
        store.setDynamicStrainNutrition(enabled: true)
        store.realHistory[todayIso] = RealBiometricDaySummary(dateIso: todayIso, strain21: 16.5, strainPct: 79, recoveryPct: 78)
        store.dataRevision += 1
        let highSnap = store.dynamicStrainNutritionSnapshot
        XCTAssertTrue(highSnap.isHighLoad)
        XCTAssertGreaterThan(highSnap.kcalDelta, 200)
        XCTAssertGreaterThan(highSnap.carbsDeltaG, 45)
        XCTAssertGreaterThanOrEqual(highSnap.extraHydrationMl, 500)
        let highGoals = store.effectiveNutritionGoals

        store.realHistory[todayIso] = RealBiometricDaySummary(dateIso: todayIso, strain21: 4.5, strainPct: 21, recoveryPct: 78)
        store.dataRevision += 1
        let restSnap = store.dynamicStrainNutritionSnapshot
        XCTAssertTrue(restSnap.isRestDay)
        XCTAssertLessThan(restSnap.kcalDelta, 0)
        XCTAssertLessThan(restSnap.carbsDeltaG, 0)
        XCTAssertGreaterThan(restSnap.proteinDeltaG, 0)
        let restGoals = store.effectiveNutritionGoals
        XCTAssertGreaterThan(highGoals.carbsG, restGoals.carbsG + 60)

        // 3. 30-day & 6-month Journal Trends (Recovery, Sleep, HRV, Stress) + Coach Personality & Archive
        let cal = Calendar.current
        for back in 1...40 {
            let d = cal.date(byAdding: .day, value: -back, to: store.selectedDate)!
            let iso = store.isoFormatter.string(from: d)
            let isYes = (back % 2 == 0)
            store.journalCheckinsByDate[iso] = ["magnesium": isYes ? .yes : .no]
            store.realHistory[iso] = RealBiometricDaySummary(
                dateIso: iso,
                restingHrBpm: isYes ? 50.0 : 55.0,
                hrvMs: isYes ? 78.0 : 62.0,
                deepMinutes: isYes ? 98 : 68,
                sleepPct: isYes ? 88 : 74,
                recoveryPct: isYes ? 82 : 64,
                stressScore: isYes ? 28 : 44
            )
            // Cross-domain meals: high protein & early dinner vs low protein & late dinner + late caffeine
            store.mealsByDate[iso] = [
                NutritionMealItem(
                    id: "cm_\(back)",
                    title: isYes ? "Salmón con quinoa" : "Pizza rápida",
                    timeLabel: isYes ? "19:30" : "22:00",
                    kcal: 700,
                    proteinG: isYes ? 150 : 60,
                    carbsG: 65,
                    fatG: 20,
                    qualityScore: isYes ? 90 : 52,
                    caffeineMg: isYes ? 65 : 220
                )
            ]
        }
        store.dataRevision += 1
        let hrvImpacts30 = store.computeJournalImpacts(for: .hrv, windowDays: 30)
        let magHrv = try XCTUnwrap(hrvImpacts30.first(where: { $0.id == "magnesium" }))
        XCTAssertEqual(magHrv.reliability, .high)
        XCTAssertEqual(magHrv.unitSuffix, " ms")
        XCTAssertNotEqual(magHrv.impactPct, 0)

        let stressImpacts6m = store.computeJournalImpacts(for: .stress, windowDays: 180)
        let magStress = try XCTUnwrap(stressImpacts6m.first(where: { $0.id == "magnesium" }))
        XCTAssertEqual(magStress.unitSuffix, " pts")
        XCTAssertTrue(magStress.isBeneficialImpact) // lowering stress is beneficial!

        // Cross-domain causality & Diario AI context
        let causal = store.unifiedCausalInsights
        XCTAssertTrue(causal.contains(where: { $0.id == "cross_protein_recovery" || $0.id == "cross_meal_timing_deep" || $0.id == "cross_caffeine_hrv" }))
        XCTAssertTrue(causal.contains(where: { $0.id == "cross_weather_thermal" }))
        let diarioFacts = store.buildSectionFacts(for: .diario)
        XCTAssertTrue(diarioFacts.hasData)
        let coachCtx = store.buildBiometricContextJson()
        XCTAssertTrue(coachCtx.json.contains("contexto_meteorologico_hoy"))
        XCTAssertTrue(coachCtx.json.contains("causalidad_cruzada_local"))
        XCTAssertTrue(coachCtx.json.contains("correlaciones_diario_30d_6m"))
        XCTAssertTrue(coachCtx.json.contains("nutricion_dinamica_strain"))

        // 4. Agentic Tools #13 (create_strength_routine) & #14 (propose_macro_meals) + 1-Tap Undo + 1-Tap Meal Log
        let rtRes = store.executeCoachToolCall(
            name: "create_strength_routine",
            argsJson: #"{"name":"Empuje Recuperación Alta","category":"Fuerza","exercises":[{"name":"Press banca con barra","sets":4,"reps":8,"weight_kg":75,"primary_muscle":"Pectorales"},{"name":"Press militar","sets":3,"reps":10,"weight_kg":40,"primary_muscle":"Hombros"}]}"#
        )
        let rtAction = try XCTUnwrap(rtRes.appliedAction)
        let rtId = try XCTUnwrap(rtAction.launchedRoutineId)
        XCTAssertTrue(store.workoutRoutines.contains(where: { $0.id == rtId && $0.exercises.count == 2 }))
        store.launchStrengthRoutineById(rtId)
        XCTAssertEqual(store.pendingLaunchRoutine?.id, rtId)

        let mealPropRes = store.executeCoachToolCall(
            name: "propose_macro_meals",
            argsJson: #"{"options":[{"title":"Bowl de salmón y arroz","emoji":"🍣","description":"180g salmón, 200g arroz, aguacate","kcal":680,"protein_g":46,"carbs_g":64,"fat_g":22,"fiber_g":7,"quality_score":92},{"title":"Tortilla de claras y boniato","emoji":"🍳","description":"5 claras, 2 huevos, 250g boniato","kcal":540,"protein_g":42,"carbs_g":58,"fat_g":14,"fiber_g":8,"quality_score":90}]}"#
        )
        let mealAction = try XCTUnwrap(mealPropRes.appliedAction)
        XCTAssertEqual(mealAction.suggestedMeals.count, 2)
        let msg = CoachChatMessage(id: "msg_test_1", isUser: false, text: "Aquí tienes 2 opciones", timestampLabel: "21:00", isSuggestionChip: false, appliedActions: [mealAction, rtAction])
        store.coachMessages = [msg]
        let firstOptId = try XCTUnwrap(mealAction.suggestedMeals.first?.id)
        store.logSuggestedMealFromCoach(messageId: msg.id, actionId: mealAction.id, optionId: firstOptId)
        XCTAssertTrue(store.mealsToday.contains(where: { $0.title == "Bowl de salmón y arroz" }))
        XCTAssertTrue(store.coachMessages[0].appliedActions[0].suggestedMeals[0].isLogged)

        // Undo created routine
        store.undoCoachAction(messageId: msg.id, actionId: rtAction.id)
        XCTAssertFalse(store.workoutRoutines.contains(where: { $0.id == rtId }))

        // 5. Coach Personality + Detail + Insights Archive persistence round-trip
        store.setCoachPersonality(tone: .cientifico, detail: .detallado)
        store.archiveAiInsight(section: .diario, emoji: "📓", headline: "Tu VFC responde al magnesio", body: "En 30 días tu VFC subió con magnesio y cena temprana.")
        store.flushPersistenceNow()

        let reloaded = ImprovingStore(persistenceURL: storeUrl)
        XCTAssertEqual(reloaded.weatherCityName, "Valencia")
        XCTAssertEqual(reloaded.weatherSnapshot?.temperatureC, 31.5)
        XCTAssertEqual(reloaded.coachPersonalityTone, .cientifico)
        XCTAssertEqual(reloaded.coachDetailLevel, .detallado)
        XCTAssertEqual(reloaded.archivedAiInsights.count, 1)
        XCTAssertTrue(reloaded.dynamicStrainNutritionEnabled)
    }

    @MainActor
    func testPerfectAISupremacySleepGatedRecoveryTwinRadarSimulatorAnd19Tools() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("improving_aiv2_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let storeUrl = tmpDir.appendingPathComponent("store.json")
        let store = ImprovingStore(persistenceURL: storeUrl)
        store.hasImportedOrPairedRealData = true
        let todayIso = store.selectedDateIso

        // 1. Strict Sleep-Gated Recovery Rule: NO sleep record -> recoveryPct MUST be nil in importer AND hidden in Store!
        let noSleepRaw = AppleHealthExportImporter.MutableAppleDay(dateIso: "2026-11-25")
        noSleepRaw.rhrValues.append(51.0)
        noSleepRaw.hrvRmssdSamples.append((1_764_060_000, 74.0))
        let builtNoSleep = AppleHealthExportImporter.buildSummaries(
            from: ["2026-11-25": noSleepRaw],
            sourceName: "Apple Watch",
            profile: store.userProfile
        )
        XCTAssertNil(builtNoSleep.days["2026-11-25"]?.recoveryPct)

        store.realHistory[todayIso] = RealBiometricDaySummary(
            dateIso: todayIso,
            restingHrBpm: 51.0,
            hrvMs: 74.0,
            recoveryPct: 82
        )
        store.dataRevision += 1
        XCTAssertFalse(store.dataAvailability.hasRecoveryData)
        XCTAssertEqual(store.recoveryPercent, 0)
        XCTAssertTrue(store.buildBiometricContextJson().json.contains("PENDIENTE_REGISTRO_SUENO"))

        // Once real sleep is recorded -> Recovery unlocks immediately!
        store.realHistory[todayIso] = RealBiometricDaySummary(
            dateIso: todayIso,
            restingHrBpm: 51.0,
            hrvMs: 74.0,
            asleepMinutes: 465,
            deepMinutes: 92,
            sleepPct: 88,
            strain21: 12.0,
            strainPct: 54,
            recoveryPct: 84,
            workouts: [
                EffortEventItem(
                    id: "wk_audit_1",
                    title: "Carrera Tempo",
                    timeRange: "08:00 - 08:50",
                    durationMin: 50,
                    avgHrBpm: 162,
                    strainScore: 14.2,
                    strainPct: 68,
                    categoryLabel: "Carrera",
                    kcal: 540,
                    dateIso: todayIso
                )
            ]
        )
        store.dataRevision += 1
        XCTAssertTrue(store.dataAvailability.hasRecoveryData)
        XCTAssertEqual(store.recoveryPercent, 84)

        // 2. Domain-Scoped Section Coaching Cache (adding water does NOT invalidate Sueño or Fitness!)
        let sleepKeyBefore = store.coachingSlotKey(for: .sueno)
        let fitKeyBefore = store.coachingSlotKey(for: .fitness)
        let diarioKeyBefore = store.coachingSlotKey(for: .diario)
        store.addNutrientAmount(key: "hidratacion", amount: 300, dateIso: todayIso)
        XCTAssertEqual(store.coachingSlotKey(for: .sueno), sleepKeyBefore)
        XCTAssertEqual(store.coachingSlotKey(for: .fitness), fitKeyBefore)
        XCTAssertNotEqual(store.coachingSlotKey(for: .diario), diarioKeyBefore)

        // 3. Subjective Contradiction Override & Proactive Immunity Radar
        let rangeBeforeSick = store.optimalEffortRange.upperBound
        store.setJournalCheck(habitId: "fever", state: .yes, for: todayIso)
        store.setJournalMood(1, for: todayIso)
        let radar = store.proactiveImmunityRadarSnapshot
        XCTAssertTrue(radar.hasActiveWarning)
        XCTAssertNotNil(radar.subjectiveMismatchText)
        XCTAssertLessThan(store.optimalEffortRange.upperBound, rangeBeforeSick)

        // 4. Full 8 Micronutrients in Meal JSON Parser & Coach `log_meal`
        let mealJson = #"{"title":"Salmón con espinacas","emoji":"🐟","kcal":610,"protein_g":44,"carbs_g":32,"fat_g":28,"fiber_g":8.5,"sugar_g":3.2,"sodium_mg":480,"potassium_mg":920,"magnesium_mg":110,"iron_mg":3.4,"vitamin_d_mcg":11.5,"omega3_g":2.4,"quality_score":94}"#
        let parsedEst = try XCTUnwrap(GeminiCoachService.parseMealEstimateJson(mealJson))
        XCTAssertEqual(parsedEst.fiberG, 8.5, accuracy: 0.05)
        XCTAssertEqual(parsedEst.omega3G, 2.4, accuracy: 0.05)
        XCTAssertEqual(parsedEst.magnesiumMg, 110, accuracy: 0.1)

        _ = store.executeCoachToolCall(name: "log_meal", argsJson: mealJson)
        let micros = store.dailyMicronutrientsSnapshot
        XCTAssertGreaterThanOrEqual(micros.first(where: { $0.id == "micro_omega3" })?.currentValue ?? 0, 2.3)

        // 5. Sanitizer preserves biomarker codes ("Vitamina D 25-OH") & strips follow-up marker cleanly
        let cleanBio = GeminiCoachService.sanitizeDirectHumanText("Tu Vitamina D (25-OH) subió bien.")
        XCTAssertTrue(cleanBio.contains("Vitamina D 25-OH"))
        XCTAssertFalse(cleanBio.contains("("))
        let stripped = GeminiCoachService.stripFollowUpMarker(from: "Buen descanso hoy.\n[[SUGERENCIAS: Crear rutina | Clavar macros | Simular noche]]")
        XCTAssertEqual(stripped.cleanText, "Buen descanso hoy.")
        XCTAssertEqual(stripped.chips.count, 3)

        // 6. Tools #15-#19 + Undo + Post-Workout Audit
        let memSave = store.executeCoachToolCall(name: "save_coach_memory", argsJson: #"{"note":"Molestia leve en gemelo derecho"}"#)
        XCTAssertTrue(store.coachMemoryNotes.contains("Molestia leve en gemelo derecho"))
        let memUpd = store.executeCoachToolCall(name: "manage_coach_memory", argsJson: #"{"action":"replace","match_text":"gemelo","new_note":"Gemelo derecho 100% recuperado"}"#)
        XCTAssertTrue(store.coachMemoryNotes.contains("Gemelo derecho 100% recuperado"))

        let simTool = store.executeCoachToolCall(name: "simulate_what_if_scenario", argsJson: #"{"sleep_hours":5.5,"alcohol_drinks":3,"caffeine_mg":160,"caffeine_hour":19,"dinner_lead_hours":1.0}"#)
        let simAct = try XCTUnwrap(simTool.appliedAction)
        let simRes = try XCTUnwrap(simAct.simulationResult)
        XCTAssertLessThan(simRes.recoveryDeltaPct, 0)
        XCTAssertFalse(simRes.mitigationSteps.isEmpty)

        let microTool = store.executeCoachToolCall(name: "generate_weekly_microcycle", argsJson: #"{"title":"Media Maratón Donosti","sport_focus":"Carrera / Resistencia","target_date_iso":"2026-12-20"}"#)
        let microAct = try XCTUnwrap(microTool.appliedAction)
        XCTAssertNotNil(store.adaptiveMicrocycleSnapshot)
        XCTAssertEqual(store.adaptiveMicrocycleSnapshot?.days.count, 7)

        let modeTool = store.executeCoachToolCall(name: "set_goal_and_sleep_mode", argsJson: #"{"goal_mode":"Rendimiento","sleep_mode_pct":100}"#)
        XCTAssertEqual(store.globalGoalMode, .rendimiento)

        // Undo memory & microcycle
        let mTest = CoachChatMessage(id: "m_v2", isUser: false, text: "Listo", timestampLabel: "12:00", isSuggestionChip: false, appliedActions: [
            try XCTUnwrap(memSave.appliedAction),
            try XCTUnwrap(memUpd.appliedAction),
            microAct,
            try XCTUnwrap(modeTool.appliedAction)
        ])
        store.coachMessages = [mTest]
        store.undoCoachAction(messageId: "m_v2", actionId: microAct.id)
        XCTAssertNil(store.activeGoalEventPlan)

        // Post-workout audit check
        let wk = try XCTUnwrap(store.workoutsToday.first)
        let audit = store.postWorkoutAudit(for: wk)
        XCTAssertGreaterThan(audit.glycogenRefillCarbsG, 20)
        XCTAssertGreaterThan(audit.rehydrationMl, 350)

        // Multi-turn history preserves appliedActions recap!
        let normContents = await GeminiCoachService.shared.buildNormalizedGeminiContents(
            history: [CoachChatMessage(id: "h1", isUser: true, text: "Simula", timestampLabel: "11:59", isSuggestionChip: false), mTest],
            currentPrompt: "¿Qué opinas?"
        )
        let serializedHistory = String(data: try JSONSerialization.data(withJSONObject: normContents), encoding: .utf8) ?? ""
        XCTAssertTrue(serializedHistory.contains("Acciones aplicadas en la app"))
    }
}
