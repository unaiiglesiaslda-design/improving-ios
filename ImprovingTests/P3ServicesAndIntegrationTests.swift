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
}
