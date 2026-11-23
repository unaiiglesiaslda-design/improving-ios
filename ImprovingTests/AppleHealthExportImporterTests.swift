import XCTest
@testable import Improving

final class AppleHealthExportImporterTests: XCTestCase {

    private let sampleXml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE HealthData [
    <!ELEMENT HealthData (Record*,Workout*)>
    <!ATTLIST Record broken_dtd_test CDATA #IMPLIED>
    ]>
    <HealthData locale="es_ES">
      <!-- Simulated malformed third-party metadata that would abort libxml2 Foundation.XMLParser -->
      <Record type="HKQuantityTypeIdentifierStepCount" unit="count" sourceName="ThirdParty & Unescaped <App>" startDate="2026-11-19 10:00:00 +0100" endDate="2026-11-19 11:00:00 +0100" value="4200">
        <MetadataEntry key="Note" value="Bad & unescaped entity"/>
      </Record>
      <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" sourceName="Apple Watch de Unai" startDate="2026-11-20 03:15:00 +0100" endDate="2026-11-20 03:15:00 +0100" value="74.0"/>
      <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" sourceName="Apple Watch de Unai" startDate="2026-11-20 05:15:00 +0100" endDate="2026-11-20 05:15:00 +0100" value="80.0"/>
      <Record type="HKQuantityTypeIdentifierRestingHeartRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 06:00:00 +0100" endDate="2026-11-20 06:00:00 +0100" value="48.5"/>
      <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 02:10:00 +0100" endDate="2026-11-20 02:10:00 +0100" value="52.0"/>
      <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 04:10:00 +0100" endDate="2026-11-20 04:10:00 +0100" value="54.0"/>
      <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 12:05:00 +0100" endDate="2026-11-20 12:05:00 +0100" value="72.0"/>
      <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 12:10:00 +0100" endDate="2026-11-20 12:10:00 +0100" value="78.0"/>
      <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 12:15:00 +0100" endDate="2026-11-20 12:15:00 +0100" value="66.0"/>
      <Record type="HKQuantityTypeIdentifierRespiratoryRate" unit="count/min" sourceName="Apple Watch de Unai" startDate="2026-11-20 04:00:00 +0100" endDate="2026-11-20 04:00:00 +0100" value="15.0"/>
      <Record type="HKQuantityTypeIdentifierOxygenSaturation" unit="%" sourceName="Apple Watch de Unai" startDate="2026-11-20 04:30:00 +0100" endDate="2026-11-20 04:30:00 +0100" value="0.98"/>
      <Record type="HKQuantityTypeIdentifierAppleSleepingWristTemperature" unit="degC" startDate="2026-11-19 06:00:00 +0100" endDate="2026-11-19 06:00:00 +0100" value="35.6"/>
      <Record type="HKQuantityTypeIdentifierAppleSleepingWristTemperature" unit="degC" startDate="2026-11-20 06:00:00 +0100" endDate="2026-11-20 06:00:00 +0100" value="35.9"/>
      <Record type="HKQuantityTypeIdentifierStepCount" unit="count" startDate="2026-11-20 09:00:00 +0100" endDate="2026-11-20 10:00:00 +0100" value="5200"/>
      <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch de Unai" value="HKCategoryValueSleepAnalysisInBed" startDate="2026-11-20 00:50:00 +0100" endDate="2026-11-20 07:35:00 +0100"/>
      <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch de Unai" value="HKCategoryValueSleepAnalysisAsleepDeep" startDate="2026-11-20 01:00:00 +0100" endDate="2026-11-20 02:30:00 +0100"/>
      <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch de Unai" value="HKCategoryValueSleepAnalysisAsleepDeep" startDate="2026-11-20 01:30:00 +0100" endDate="2026-11-20 02:30:00 +0100"/>
      <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch de Unai" value="HKCategoryValueSleepAnalysisAsleepREM" startDate="2026-11-20 02:30:00 +0100" endDate="2026-11-20 04:00:00 +0100"/>
      <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch de Unai" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-11-20 04:00:00 +0100" endDate="2026-11-20 07:30:00 +0100"/>
      <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="42" durationUnit="min" totalEnergyBurned="490" totalEnergyBurnedUnit="kcal" startDate="2026-11-20 18:00:00 +0100" endDate="2026-11-20 18:42:00 +0100">
        <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" average="152" unit="count/min"/>
      </Workout>
    </HealthData>
    """

    func testFaultTolerantScannerExtractsHRVAndSleepAfterMalformedXML() throws {
        let data = try XCTUnwrap(sampleXml.data(using: .utf8))
        let res = AppleHealthExportImporter.parseXmlData(data)
        XCTAssertNil(res.errorMessage)
        let day = try XCTUnwrap(res.days["2026-11-20"])
        XCTAssertEqual(day.hrvMs ?? 0, 77.0, accuracy: 0.2)
        XCTAssertEqual(day.restingHrBpm ?? 0, 48.5, accuracy: 0.1)
        XCTAssertEqual(day.spo2Percent ?? 0, 98.0, accuracy: 0.2)
        XCTAssertEqual(day.deepMinutes, 90)
        XCTAssertEqual(day.remMinutes, 90)
        XCTAssertEqual(day.asleepMinutes, 390)
        XCTAssertEqual(day.stepsCount, 5200)
        XCTAssertEqual(day.workouts.count, 1)
        XCTAssertEqual(day.workouts.first?.title, "Carrera")
        XCTAssertEqual(day.workouts.first?.avgHrBpm, 152)
        // Daytime HR must exclude sleeping HR samples (52, 54) -> mean of (72, 78, 66) = 72
        XCTAssertEqual(day.liveHrBpm, 72)

        XCTAssertGreaterThanOrEqual(day.stressSamples5m.count, 5)
        XCTAssertGreaterThanOrEqual(day.energySamples5m.count, 5)

        let sess = try XCTUnwrap(day.sleepSession)
        XCTAssertEqual(sess.sourceName, "Apple Watch de Unai")
        XCTAssertEqual(sess.latencyMinutes, 10)
        XCTAssertFalse(sess.stages.isEmpty)
        XCTAssertFalse(sess.sleepHrSamples.isEmpty)
        XCTAssertFalse(sess.sleepHrvSamples.isEmpty)
        XCTAssertFalse(sess.sleepRespSamples.isEmpty)
        XCTAssertFalse(sess.sleepSpo2Samples.isEmpty)
    }

    func testContinuousCrossDayEnergyBankCarriesExactEndingAcrossMidnight() throws {
        let twoDayXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKQuantityTypeIdentifierRestingHeartRate" unit="count/min" startDate="2026-11-20 06:00:00 +0100" endDate="2026-11-20 06:00:00 +0100" value="52"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-20 09:00:00 +0100" endDate="2026-11-20 09:00:00 +0100" value="92"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-20 14:00:00 +0100" endDate="2026-11-20 14:00:00 +0100" value="110"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-20 19:00:00 +0100" endDate="2026-11-20 19:00:00 +0100" value="105"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-20 23:55:00 +0100" endDate="2026-11-20 23:55:00 +0100" value="84"/>
          <Record type="HKQuantityTypeIdentifierRestingHeartRate" unit="count/min" startDate="2026-11-21 06:00:00 +0100" endDate="2026-11-21 06:00:00 +0100" value="52"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-21 00:01:00 +0100" endDate="2026-11-21 00:01:00 +0100" value="80"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-21 00:10:00 +0100" endDate="2026-11-21 00:10:00 +0100" value="76"/>
        </HealthData>
        """
        let data = try XCTUnwrap(twoDayXml.data(using: .utf8))
        let res = AppleHealthExportImporter.parseXmlData(data)
        let day1 = try XCTUnwrap(res.days["2026-11-20"])
        let day2 = try XCTUnwrap(res.days["2026-11-21"])
        let endDay1 = try XCTUnwrap(day1.energySamples5m.last?.value)
        let startDay2 = try XCTUnwrap(day2.energySamples5m.first?.value)
        // Day 2 at 00:01 MUST start at EXACTLY Day 1's ending energy (zero midnight jump!)
        XCTAssertEqual(startDay2, endDay1, accuracy: 0.15)
    }

    func testBeatToBeatHRVFallbackWhenScalarValueMissing() throws {
        let bpmFallbackXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-20 04:00:00 +0100" endDate="2026-11-20 04:01:00 +0100">
            <InstantaneousBeatsPerMinute bpm="56" time="04:00:01"/>
            <InstantaneousBeatsPerMinute bpm="60" time="04:00:02"/>
            <InstantaneousBeatsPerMinute bpm="55" time="04:00:03"/>
            <InstantaneousBeatsPerMinute bpm="61" time="04:00:04"/>
            <InstantaneousBeatsPerMinute bpm="57" time="04:00:05"/>
          </Record>
        </HealthData>
        """
        let data = try XCTUnwrap(bpmFallbackXml.data(using: .utf8))
        let res = AppleHealthExportImporter.parseXmlData(data)
        let day = try XCTUnwrap(res.days["2026-11-20"])
        XCTAssertNotNil(day.hrvMs)
        XCTAssertGreaterThan(day.hrvMs ?? 0, 20.0)
    }

    func testZeroFabricationOnSparseXmlDay() throws {
        let sparseXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKQuantityTypeIdentifierStepCount" unit="count" startDate="2026-11-18 10:00:00 +0100" endDate="2026-11-18 11:00:00 +0100" value="3100"/>
        </HealthData>
        """
        let data = try XCTUnwrap(sparseXml.data(using: .utf8))
        let res = AppleHealthExportImporter.parseXmlData(data)
        let day = try XCTUnwrap(res.days["2026-11-18"])
        XCTAssertEqual(day.stepsCount, 3100)
        XCTAssertNil(day.hrvMs)
        XCTAssertNil(day.restingHrBpm)
        XCTAssertNil(day.spo2Percent)
        XCTAssertNil(day.asleepMinutes)
        XCTAssertNil(day.sleepSession)
        XCTAssertNil(day.stressScore)
        XCTAssertNil(day.energyBankPercent)
        XCTAssertNil(day.recoveryPct)
        XCTAssertTrue(day.stressSamples5m.isEmpty)
    }

    func testPhysiologyEngineRecoveryAndEffort() {
        let rec = WhoopPhysiologyEngine.computeRecoveryPercent(
            hrvMs: 82, rhrBpm: 48, respRpm: 15.0, spo2Pct: 98.0, wristTempDeltaC: 0.0, sleepScorePct: 90
        )
        XCTAssertTrue((60...99).contains(rec))

        // Returns nil if neither HRV nor RHR exists
        let nilRec = WhoopPhysiologyEngine.computeBevelRecoveryPercent(
            hrvMs: nil,
            rhrBpm: nil,
            respRpm: 15.0,
            spo2Pct: 98.0,
            wristTempDeltaC: 0.0,
            lnHrvBaseline: PersonalBaselineStats(mean: log(70.0), sigma: 0.2, count: 30),
            rhrBaseline: PersonalBaselineStats(mean: 52.0, sigma: 2.5, count: 30),
            respBaseline: PersonalBaselineStats(mean: 15.0, sigma: 0.6, count: 30)
        )
        XCTAssertNil(nilRec)

        // Calibrated Bevel workout strain for 300 kcal strength session should be ~20-35% (not inflated!)
        let wk = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: 45, kcal: 300, avgHrBpm: 0)
        XCTAssertTrue((15...35).contains(wk.strainPct))

        let range = WhoopPhysiologyEngine.optimalTargetRange(for: rec)
        XCTAssertLessThan(range.lowerBound, range.upperBound)
    }

    @MainActor
    func testDiario20ManualItemsCompletionAnd30DayInsightLock() {
        let store = ImprovingStore()
        store.hasImportedOrPairedRealData = true
        store.journalCheckinsByDate = [:]
        store.journalMoodByDate = [:]
        store.hydrationGlassesByDate = [:]
        store.realHistory = [:]

        let todayIso = store.selectedDateIso
        // 19 manual items -> NOT completed yet
        for id in ImprovingStore.manualHabitIds.prefix(19) {
            store.setJournalCheck(habitId: id, state: .yes)
        }
        XCTAssertEqual(store.manualCompletedCount(for: todayIso), 19)
        XCTAssertFalse(store.isDiarioDayCompleted(for: todayIso))

        // 20th manual item -> Completed!
        store.setJournalCheck(habitId: ImprovingStore.manualHabitIds[19], state: .no)
        XCTAssertEqual(store.manualCompletedCount(for: todayIso), 20)
        XCTAssertTrue(store.isDiarioDayCompleted(for: todayIso))

        // Empty Diario -> ZERO unlocked insights!
        store.journalCheckinsByDate = [:]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for back in 0..<35 {
            let dt = cal.date(byAdding: .day, value: -back, to: today)!
            let iso = store.isoFormatter.string(from: dt)
            store.realHistory[iso] = RealBiometricDaySummary(dateIso: iso, sleepPct: 80, recoveryPct: 75, stepsCount: back % 2 == 0 ? 12000 : 4000)
        }
        let emptyImpacts = store.computeJournalImpacts(for: .recovery)
        XCTAssertTrue(emptyImpacts.allSatisfy { $0.reliability == .locked })

        // 15 days of manual logging -> STILL locked (< 30 days!)
        for back in 0..<15 {
            let dt = cal.date(byAdding: .day, value: -back, to: today)!
            let iso = store.isoFormatter.string(from: dt)
            store.journalCheckinsByDate[iso] = ["caffeine": back % 2 == 0 ? .yes : .no]
        }
        let day15Impacts = store.computeJournalImpacts(for: .recovery)
        XCTAssertEqual(day15Impacts.first(where: { $0.id == "caffeine" })?.reliability, .locked)

        // 32 days of manual logging with >=5 yes and >=5 no -> UNLOCKS high reliability!
        for back in 0..<32 {
            let dt = cal.date(byAdding: .day, value: -back, to: today)!
            let iso = store.isoFormatter.string(from: dt)
            store.journalCheckinsByDate[iso] = ["caffeine": back % 2 == 0 ? .yes : .no]
            store.realHistory[iso]?.recoveryPct = back % 2 == 0 ? 68 : 82
        }
        let day32Impacts = store.computeJournalImpacts(for: .recovery)
        let caf = day32Impacts.first(where: { $0.id == "caffeine" })
        XCTAssertEqual(caf?.reliability, .high)
        XCTAssertEqual(caf?.impactPct, -14)
    }
}
