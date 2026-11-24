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

    func testShortcutsEnvelopeSpanishDatesSleepAndContinuousEnergy() throws {
        // Prior day ending at 19.0% energy
        var prior: [String: RealBiometricDaySummary] = [:]
        prior["2026-11-22"] = RealBiometricDaySummary(
            dateIso: "2026-11-22",
            restingHrBpm: 50.0,
            hrvMs: 70.0,
            energyBankPercent: 19,
            energySamples5m: [TimedBiometricPoint(minuteOfDay: 1435, value: 19.0, epochSec: nil)]
        )

        let env = ShortcutsSyncEnvelope(
            source: "Atajos de Apple",
            hrValues: ["52 lat/min", "54 lat/min", "74 lat/min", "82 lat/min"],
            hrDates: ["23/11/2026, 0:05", "23/11/2026, 4:00", "23/11/2026, 10:15", "23/11/2026, 13:30"],
            hrvValues: ["71,4 ms", "76,6 ms"],
            hrvDates: ["23/11/2026, 3:15", "23/11/2026, 5:45"],
            rhrValues: ["49,5"],
            rhrDates: ["23/11/2026, 6:30"],
            respValues: ["15,1 rpm"],
            respDates: ["23/11/2026, 4:00"],
            spo2Values: ["98 %"],
            spo2Dates: ["23/11/2026, 4:30"],
            stepsValues: ["5.420 pasos"],
            stepsDates: ["23/11/2026, 12:00"],
            kcalValues: ["410 kcal"],
            kcalDates: ["23/11/2026, 12:00"],
            sleepValues: ["Dormido (Profundo)", "Dormido (REM)", "Dormido (Esencial)"],
            sleepStarts: ["23/11/2026, 1:00", "23/11/2026, 2:30", "23/11/2026, 4:00"],
            sleepEnds: ["23/11/2026, 2:30", "23/11/2026, 4:00", "23/11/2026, 7:30"]
        )

        let res = ShortcutsHealthSyncImporter.parseEnvelope(env, priorHistory: prior)
        XCTAssertNil(res.errorMessage)
        let day = try XCTUnwrap(res.days["2026-11-23"])
        XCTAssertEqual(day.hrvMs ?? 0, 74.0, accuracy: 0.2)
        XCTAssertEqual(day.restingHrBpm ?? 0, 49.5, accuracy: 0.2)
        XCTAssertEqual(day.stepsCount, 5420)
        XCTAssertEqual(day.activeKcal, 410)
        XCTAssertEqual(day.deepMinutes, 90)
        XCTAssertEqual(day.remMinutes, 90)
        XCTAssertEqual(day.asleepMinutes, 390)
        XCTAssertNotNil(day.recoveryPct)
        XCTAssertNotNil(day.sleepPct)
        // Energy at 00:05 MUST carry over continuously from yesterday's 19.0% (zero jump!)
        let firstEnergy = try XCTUnwrap(day.energySamples5m.first?.value)
        XCTAssertEqual(firstEnergy, 19.0, accuracy: 0.2)
    }

    func testShortcutsPipeLinesAndHealthAutoExportJson() throws {
        let pipeText = """
        hr|2026-11-23 09:00:00 +0100|68
        hrv|2026-11-23 05:00:00 +0100|66,5
        rhr|2026-11-23 06:00:00 +0100|51
        steps|2026-11-23 11:00:00 +0100|6100
        """
        let res1 = ShortcutsHealthSyncImporter.parseRawText(pipeText)
        let d1 = try XCTUnwrap(res1.days["2026-11-23"])
        XCTAssertEqual(d1.hrvMs ?? 0, 66.5, accuracy: 0.2)
        XCTAssertEqual(d1.stepsCount, 6100)

        let haeJson = """
        {
          "data": {
            "metrics": [
              {"name": "heart_rate_variability", "units": "ms", "data": [{"date": "2026-11-23 04:00:00 +0100", "qty": 72.5}]},
              {"name": "resting_heart_rate", "units": "count/min", "data": [{"date": "2026-11-23 06:00:00 +0100", "qty": 48.0}]},
              {"name": "step_count", "units": "count", "data": [{"date": "2026-11-23 12:00:00 +0100", "qty": 8200}]}
            ]
          }
        }
        """
        let res2 = ShortcutsHealthSyncImporter.parseData(try XCTUnwrap(haeJson.data(using: .utf8)))
        let d2 = try XCTUnwrap(res2.days["2026-11-23"])
        XCTAssertEqual(d2.hrvMs ?? 0, 72.5, accuracy: 0.2)
        XCTAssertEqual(d2.restingHrBpm ?? 0, 48.0, accuracy: 0.2)
        XCTAssertEqual(d2.stepsCount, 8200)
    }

    func testShortcutsThreeDecimalActiveCaloriesDoesNotInflateStrainTo100() throws {
        // Reproduces real Apple Watch Shortcuts export: 3-decimal active kcal samples ("1.245", "2.318", ...),
        // 3-decimal HRV ("68.412") + seconds HRV ("0.072"), Spanish "a la" / "a las" dates, and Watch+iPhone duplicates!
        let json = """
        {
          "hr_values": "64.125\\n72.250\\n68.500\\n74.000\\n74.000",
          "hr_dates": "23 nov 2026 a la 1:05\\n23 nov 2026 a las 9:15\\n23/11/26 11:30\\n23/11/26, 13:45\\n23/11/26, 13:45",
          "hrv_values": "68.412\\n0.072",
          "hrv_dates": "23 nov 2026 a las 4:10\\n23 nov 2026 a las 5:30",
          "rhr_values": "52.125",
          "rhr_dates": "23 nov 2026 a las 6:00",
          "kcal_values": "1.245\\n2.318\\n1.612\\n3.050\\n1.893\\n2.456\\n1.245\\n4.125\\n1.500\\n2.100\\n12.450\\n8.320\\n15.100\\n18.600\\n6.250",
          "kcal_dates": "23 nov 2026 a las 8:05\\n23 nov 2026 a las 8:10\\n23 nov 2026 a las 8:15\\n23 nov 2026 a las 8:20\\n23 nov 2026 a las 8:25\\n23 nov 2026 a las 8:30\\n23 nov 2026 a las 8:05\\n23 nov 2026 a las 9:00\\n23 nov 2026 a las 9:10\\n23 nov 2026 a las 9:20\\n23 nov 2026 a las 10:00\\n23 nov 2026 a las 10:30\\n23 nov 2026 a las 11:00\\n23 nov 2026 a las 12:00\\n23 nov 2026 a las 13:00",
          "steps_values": "5.420\\n5.420",
          "steps_dates": "23 nov 2026 a las 12:00\\n23 nov 2026 a las 12:00"
        }
        """
        let res = ShortcutsHealthSyncImporter.parseData(try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertNil(res.errorMessage)
        let day = try XCTUnwrap(res.days["2026-11-23"])

        // Real deduplicated sum is ~81 kcal (NOT 45,000+ kcal!)
        XCTAssertEqual(Double(day.activeKcal ?? 0), 81.0, accuracy: 2.0)
        // Strain for 81 kcal passive morning MUST be low (~4-10%), NEVER 100%!
        let strain = try XCTUnwrap(day.strainPct)
        XCTAssertLessThan(strain, 20)
        // 3-decimal HRV ("68.412") + seconds HRV ("0.072" -> 72.0) -> mean ~70.2 ms
        XCTAssertEqual(day.hrvMs ?? 0, 70.2, accuracy: 0.3)
        // 3-decimal RHR ("52.125") must NOT be turned into 52125 and dropped!
        XCTAssertEqual(day.restingHrBpm ?? 0, 52.1, accuracy: 0.2)
        // Steps "5.420" parsed as 5420 AND duplicate timestamp deduplicated (not 10840!)
        XCTAssertEqual(day.stepsCount, 5420)
    }

    func testBeatToBeatRMSSDPreferredOverSDNNInAppleHealthXml() throws {
        // Apple Health XML record with BOTH scalar SDNN (value="42.0") AND beat-to-beat <InstantaneousBeatsPerMinute>
        // (including an ectopic artifact bpm="180" that Bevel/WHOOP artifact filter must reject!).
        // Alternating RR: 56 bpm (1071.4ms), 60 bpm (1000.0ms), 55 bpm (1090.9ms), 61 bpm (983.6ms), 57 bpm (1052.6ms), 60 bpm (1000.0ms) -> RMSSD ~82ms >> SDNN 42ms!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-11-23 01:00:00 +0100" endDate="2026-11-23 07:30:00 +0100"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" sourceName="Apple Watch" startDate="2026-11-23 03:30:00 +0100" endDate="2026-11-23 03:31:00 +0100" value="42.0">
            <HeartRateVariabilityMetadataList>
              <InstantaneousBeatsPerMinute bpm="56" time="03:30:01"/>
              <InstantaneousBeatsPerMinute bpm="60" time="03:30:02"/>
              <InstantaneousBeatsPerMinute bpm="180" time="03:30:03"/>
              <InstantaneousBeatsPerMinute bpm="55" time="03:30:04"/>
              <InstantaneousBeatsPerMinute bpm="61" time="03:30:05"/>
              <InstantaneousBeatsPerMinute bpm="57" time="03:30:06"/>
              <InstantaneousBeatsPerMinute bpm="60" time="03:30:07"/>
              <InstantaneousBeatsPerMinute bpm="56" time="03:30:08"/>
            </HeartRateVariabilityMetadataList>
          </Record>
        </HealthData>
        """
        let res = AppleHealthExportImporter.parseXmlData(try XCTUnwrap(xml.data(using: .utf8)))
        let day = try XCTUnwrap(res.days["2026-11-23"])
        XCTAssertEqual(day.hrvMethodLabel, "RMSSD · Todo el sueño")
        // Must compute true beat-to-beat RMSSD (~70-95 ms), NOT Apple's 42.0 SDNN!
        XCTAssertGreaterThan(day.hrvMs ?? 0, 65.0)
        XCTAssertLessThan(day.hrvMs ?? 999, 105.0)
    }

    func testEntireSleepClusteringExcludesDaytimeHRVAndNextNightBedtime() throws {
        // Pre-midnight sleep (23:15-23:55 prev day) + overnight sleep (00:00-07:30)
        // + LOW daytime stress HRV (26 ms, 31 ms at 14:00 & 17:00)
        // + next-night bedtime block (23:20-23:55 today) which previously stretched the sleep window across the whole day!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-11-22 23:15:00 +0100" endDate="2026-11-22 23:55:00 +0100"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-22 23:30:00 +0100" endDate="2026-11-22 23:31:00 +0100" value="72.0"/>
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepDeep" startDate="2026-11-23 00:00:00 +0100" endDate="2026-11-23 02:30:00 +0100"/>
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepREM" startDate="2026-11-23 02:30:00 +0100" endDate="2026-11-23 07:30:00 +0100"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 02:00:00 +0100" endDate="2026-11-23 02:01:00 +0100" value="68.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 05:00:00 +0100" endDate="2026-11-23 05:01:00 +0100" value="78.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 07:00:00 +0100" endDate="2026-11-23 07:01:00 +0100" value="70.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 14:00:00 +0100" endDate="2026-11-23 14:01:00 +0100" value="26.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 17:00:00 +0100" endDate="2026-11-23 17:01:00 +0100" value="31.0"/>
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisInBed" startDate="2026-11-23 23:20:00 +0100" endDate="2026-11-23 23:55:00 +0100"/>
        </HealthData>
        """
        let res = AppleHealthExportImporter.parseXmlData(try XCTUnwrap(xml.data(using: .utf8)))
        let day = try XCTUnwrap(res.days["2026-11-23"])
        // Must average ONLY the 4 Entire Sleep readings: (72 + 68 + 78 + 70) / 4 = 72.0 ms (daytime 26 & 31 MUST be excluded!)
        XCTAssertEqual(day.hrvMs ?? 0, 72.0, accuracy: 0.2)
        XCTAssertEqual(day.sleepSession?.sleepHrvSamples.count, 4)
    }

    func testBevelEntireSleepExcludesInBedAndAwakeForBothHRVAndRHR() throws {
        // Reproduces exact user discrepancy (Bevel: HRV 63.0 / RHR 50.7 vs contaminated InBed+Awake: HRV 48.8 / RHR 61.4):
        // - iPhone InBed schedule while still awake: 23:30-03:15 (HR 76/78/80, HRV 28/30)
        // - Actual Apple Watch sleep: 03:15-06:00 & 06:25-11:00 (HR 50.0/51.0/50.5/51.3 -> mean 50.7, HRV 60/66 -> mean 63.0)
        // - Mid-night Awake interruption: 06:00-06:25 (HR 79, HRV 32)
        // - Apple daytime RHR: 61.0
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="iPhone" value="HKCategoryValueSleepAnalysisInBed" startDate="2026-11-22 23:30:00 +0100" endDate="2026-11-23 03:15:00 +0100"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 00:30:00 +0100" endDate="2026-11-23 00:30:00 +0100" value="76"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 01:30:00 +0100" endDate="2026-11-23 01:30:00 +0100" value="78"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 02:30:00 +0100" endDate="2026-11-23 02:30:00 +0100" value="80"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 01:00:00 +0100" endDate="2026-11-23 01:01:00 +0100" value="28"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 02:00:00 +0100" endDate="2026-11-23 02:01:00 +0100" value="30"/>

          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-11-23 03:15:00 +0100" endDate="2026-11-23 06:00:00 +0100"/>
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAwake" startDate="2026-11-23 06:00:00 +0100" endDate="2026-11-23 06:25:00 +0100"/>
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepDeep" startDate="2026-11-23 06:25:00 +0100" endDate="2026-11-23 11:00:00 +0100"/>

          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 04:00:00 +0100" endDate="2026-11-23 04:00:00 +0100" value="50.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 05:00:00 +0100" endDate="2026-11-23 05:00:00 +0100" value="51.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 06:12:00 +0100" endDate="2026-11-23 06:12:00 +0100" value="79.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 07:30:00 +0100" endDate="2026-11-23 07:30:00 +0100" value="50.5"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" unit="count/min" startDate="2026-11-23 09:30:00 +0100" endDate="2026-11-23 09:30:00 +0100" value="51.3"/>

          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 04:30:00 +0100" endDate="2026-11-23 04:31:00 +0100" value="60.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 06:12:00 +0100" endDate="2026-11-23 06:13:00 +0100" value="32.0"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 08:30:00 +0100" endDate="2026-11-23 08:31:00 +0100" value="66.0"/>
          <Record type="HKQuantityTypeIdentifierRestingHeartRate" unit="count/min" startDate="2026-11-23 12:00:00 +0100" endDate="2026-11-23 12:00:00 +0100" value="61.0"/>
        </HealthData>
        """
        let res = AppleHealthExportImporter.parseXmlData(try XCTUnwrap(xml.data(using: .utf8)))
        let day = try XCTUnwrap(res.days["2026-11-23"])
        // Strictly ASLEEP HR: (50.0 + 51.0 + 50.5 + 51.3) / 4 = 50.7 bpm (excludes InBed 76/78/80, Awake 79, Apple RHR 61!)
        XCTAssertEqual(day.restingHrBpm ?? 0, 50.7, accuracy: 0.15)
        // Strictly ASLEEP HRV: (60.0 + 66.0) / 2 = 63.0 ms (excludes InBed 28/30 and Awake 32!)
        XCTAssertEqual(day.hrvMs ?? 0, 63.0, accuracy: 0.15)
        XCTAssertNotNil(day.syncDiagnosticLine)
    }

    func testSubsecondInstantaneousBeatsPerMinuteExactRMSSDAndGapSplit() throws {
        // Real Apple Health export.xml format with sub-second timestamps + a 5-second optical dropout gap!
        // Segment 1 RR: 1150, 1090, 1180, 1120 -> diffs 60, 90, 60
        // (5.0s sensor dropout gap -> must split segment!)
        // Segment 2 RR: 1150, 1090, 1180 -> diffs 60, 90
        // Exact RMSSD = sqrt((3600+8100+3600+3600+8100)/5) = sqrt(5400) = 73.5 ms
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="es_ES">
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-11-23 02:00:00 +0100" endDate="2026-11-23 08:00:00 +0100"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" startDate="2026-11-23 04:00:00 +0100" endDate="2026-11-23 04:01:00 +0100" value="42.0">
            <HeartRateVariabilityMetadataList>
              <InstantaneousBeatsPerMinute bpm="52" time="4:00:00.00 AM"/>
              <InstantaneousBeatsPerMinute bpm="52" time="4:00:01.15 AM"/>
              <InstantaneousBeatsPerMinute bpm="55" time="4:00:02.24 AM"/>
              <InstantaneousBeatsPerMinute bpm="51" time="4:00:03.42 AM"/>
              <InstantaneousBeatsPerMinute bpm="54" time="4:00:04.54 AM"/>
              <InstantaneousBeatsPerMinute bpm="52" time="4:00:09.54 AM"/>
              <InstantaneousBeatsPerMinute bpm="52" time="4:00:10.69 AM"/>
              <InstantaneousBeatsPerMinute bpm="55" time="4:00:11.78 AM"/>
              <InstantaneousBeatsPerMinute bpm="51" time="4:00:12.96 AM"/>
            </HeartRateVariabilityMetadataList>
          </Record>
        </HealthData>
        """
        let res = AppleHealthExportImporter.parseXmlData(try XCTUnwrap(xml.data(using: .utf8)))
        let day = try XCTUnwrap(res.days["2026-11-23"])
        XCTAssertEqual(day.hrvMethodLabel, "RMSSD · Todo el sueño")
        XCTAssertEqual(day.hrvMs ?? 0, 73.5, accuracy: 0.5)
    }

    @MainActor
    func testShortcutCallbackUrlAndSyncBannerLifecycle() throws {
        let url = try XCTUnwrap(ImprovingStore.buildShortcutCallbackURL(shortcutName: "Sync Improving (Automático)"))
        XCTAssertEqual(url.scheme, "shortcuts")
        XCTAssertEqual(url.host, "x-callback-url")
        XCTAssertEqual(url.path, "/run-shortcut")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "name" })?.value, "Sync Improving (Automático)")
        XCTAssertEqual(items.first(where: { $0.name == "x-success" })?.value, "improving://sync?from=shortcut_ok")

        let store = ImprovingStore()
        store.presentSyncBanner(.syncing("Sincronizando…"))
        XCTAssertEqual(store.syncBannerState, .syncing("Sincronizando…"))

        // Returning via x-cancel cleanly hides the floating bubble without looping
        let cancelUrl = try XCTUnwrap(URL(string: "improving://sync?from=shortcut_cancel"))
        store.handleIncomingURL(cancelUrl)
        XCTAssertEqual(store.syncBannerState, .hidden)

        // Returning via x-error displays brief non-blocking notice
        let errUrl = try XCTUnwrap(URL(string: "improving://sync?from=shortcut_error"))
        store.handleIncomingURL(errUrl)
        XCTAssertEqual(store.syncBannerState, .notice("Revisa nombre del atajo"))

        // Default silent mode (`autoRunShortcutOnOpen == false`): pull-to-refresh stays 100% inside Improving
        XCTAssertFalse(store.autoRunShortcutOnOpen)
    }

    func testStagedSleepIgnoresBroadDurmiendoUnspecifiedBlockExtendingToAfternoon() throws {
        // Reproduces exact real user health_sync.json pattern:
        // - Real Apple Watch staged sleep (`En la cama`, `Esencial`, `Profundo`, `REM`, `Vigilia`) from 00:05 to 08:15
        // - Secondary/third-party `"Durmiendo"` (`asleepUnspecified`) blocks extending into the afternoon (`14:16`)
        //   plus an anomalous previous-day `"Durmiendo"` crossing 18:00
        // - Real sleeping HR ~50.7 bpm, daytime awake HR 85-115 bpm up to 14:16
        // - Real sleeping HRV ~63.0 ms, yesterday evening + daytime low HRV 21-32 ms
        let json = """
        {
          "sleep_values": "Durmiendo\\nEn la cama\\nEsencial\\nProfundo\\nEsencial\\nVigilia\\nEsencial\\nREM\\nEsencial\\nDurmiendo\\nDurmiendo\\nDurmiendo",
          "sleep_starts": "22 nov 2026, 15:00\\n22 nov 2026, 23:55\\n23 nov 2026, 0:05\\n23 nov 2026, 1:30\\n23 nov 2026, 3:00\\n23 nov 2026, 4:00\\n23 nov 2026, 4:15\\n23 nov 2026, 5:45\\n23 nov 2026, 7:15\\n23 nov 2026, 8:15\\n23 nov 2026, 10:30\\n23 nov 2026, 12:30",
          "sleep_ends": "22 nov 2026, 18:30\\n23 nov 2026, 14:16\\n23 nov 2026, 1:30\\n23 nov 2026, 3:00\\n23 nov 2026, 4:00\\n23 nov 2026, 4:15\\n23 nov 2026, 5:45\\n23 nov 2026, 7:15\\n23 nov 2026, 8:15\\n23 nov 2026, 10:30\\n23 nov 2026, 12:30\\n23 nov 2026, 14:16",
          "hr_values": "78\\n50.0\\n51.0\\n50.4\\n51.4\\n88\\n94\\n105\\n98\\n86",
          "hr_dates": "22 nov 2026, 17:00\\n23 nov 2026, 0:45\\n23 nov 2026, 2:15\\n23 nov 2026, 5:00\\n23 nov 2026, 7:45\\n23 nov 2026, 9:00\\n23 nov 2026, 10:15\\n23 nov 2026, 11:30\\n23 nov 2026, 13:00\\n23 nov 2026, 14:00",
          "hrv_values": "28.0\\n31.0\\n60.0\\n66.0\\n24.0\\n29.0",
          "hrv_dates": "22 nov 2026, 17:30\\n22 nov 2026, 18:15\\n23 nov 2026, 2:00\\n23 nov 2026, 6:30\\n23 nov 2026, 11:00\\n23 nov 2026, 13:45",
          "rhr_values": "61.0",
          "rhr_dates": "23 nov 2026, 14:00"
        }
        """
        let res = ShortcutsHealthSyncImporter.parseData(try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertNil(res.errorMessage)
        let day = try XCTUnwrap(res.days["2026-11-23"])

        // Sleeping HR MUST strictly match real staged sleep (50.0+51.0+50.4+51.4)/4 = 50.7 bpm, NEVER daytime 86-105!
        XCTAssertEqual(day.restingHrBpm ?? 0, 50.7, accuracy: 0.15)
        // Sleeping HRV MUST strictly match real staged sleep (60.0+66.0)/2 = 63.0 ms, NEVER daytime 24-31!
        XCTAssertEqual(day.hrvMs ?? 0, 63.0, accuracy: 0.15)
        // Clamped sleep session MUST NOT extend to 14:16!
        XCTAssertNotEqual(day.sleepSession?.endTimeLabel, "14:16")
        // Diagnostic line MUST be cleanly formatted without `Optional(...)`!
        let diag = try XCTUnwrap(day.syncDiagnosticLine)
        XCTAssertFalse(diag.contains("Optional("))
    }

    func testMergeDaysPreservesTrueRMSSDOverShortcutsSDNN() throws {
        var existingDay = RealBiometricDaySummary(dateIso: "2026-11-23")
        existingDay.hrvMs = 63.0
        existingDay.hrvMethodLabel = "RMSSD · Todo el sueño"
        existingDay.restingHrBpm = 50.7

        var incomingShortcutsDay = RealBiometricDaySummary(dateIso: "2026-11-23")
        incomingShortcutsDay.hrvMs = 52.1
        incomingShortcutsDay.hrvMethodLabel = "SDNN · Todo el sueño"
        incomingShortcutsDay.restingHrBpm = 50.5
        incomingShortcutsDay.activeKcal = 240

        let merged = WhoopExportImporter.mergeDays(
            existing: ["2026-11-23": existingDay],
            imported: ["2026-11-23": incomingShortcutsDay]
        )
        let day = try XCTUnwrap(merged["2026-11-23"])
        // Must preserve true beat-to-beat RMSSD (63.0) rather than downgrading to Shortcuts SDNN (52.1)
        XCTAssertEqual(day.hrvMs ?? 0, 63.0, accuracy: 0.05)
        XCTAssertEqual(day.hrvMethodLabel, "RMSSD · Todo el sueño")
        // While still accepting fresh daytime activity metrics from Shortcuts!
        XCTAssertEqual(day.activeKcal, 240)
    }

    func testPersonalProfileAgeSexHeightWeightImpactsRecoveryStrainSleepBioAgeAndNutrition() throws {
        // Same sensor readings evaluated for a 19-year-old tall male vs a 64-year-old shorter female:
        var youngMale = UserPhysiologyProfile(
            userName: "Aitor",
            lastName: "Iglesias",
            ageYears: 19.0,
            sex: .male,
            weightKg: 76.0,
            heightCm: 184.0
        )
        youngMale.birthDateIso = "2007-05-10"

        var olderFemale = UserPhysiologyProfile(
            userName: "Elena",
            lastName: "Ruiz",
            ageYears: 64.0,
            sex: .female,
            weightKg: 58.0,
            heightCm: 160.0
        )
        olderFemale.birthDateIso = "1962-05-10"

        XCTAssertEqual(youngMale.initials, "AI")
        XCTAssertEqual(olderFemale.initials, "ER")
        XCTAssertLessThan(youngMale.effectiveAgeYears, 22.0)
        XCTAssertGreaterThan(olderFemale.effectiveAgeYears, 60.0)

        let youngNorms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: youngMale)
        let olderNorms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: olderFemale)

        // 1. Tanaka MaxHR, HRV expected, BMR, Hydration & Sleep targets MUST meaningfully differ!
        XCTAssertGreaterThan(youngNorms.maxHrBpm, olderNorms.maxHrBpm + 20)
        XCTAssertGreaterThan(youngNorms.hrvExpectedMs, olderNorms.hrvExpectedMs + 25.0)
        XCTAssertGreaterThan(youngNorms.bmrKcal, olderNorms.bmrKcal + 300)
        XCTAssertGreaterThan(youngNorms.hydrationGoalLiters, olderNorms.hydrationGoalLiters)
        XCTAssertGreaterThan(youngNorms.deepTargetPct, olderNorms.deepTargetPct)

        // 2. Identical 45 min workout at 142 bpm produces HIGHER cardiovascular strain for 64yo (higher % of Tanaka HRR!)
        let workout = EffortEventItem(
            id: "w1", title: "Carrera", timeRange: "10:00 - 10:45",
            durationMin: 45, avgHrBpm: 142, strainScore: 0, strainPct: 0,
            categoryLabel: "Cardio", kcal: 380
        )
        let youngStrain = try XCTUnwrap(WhoopPhysiologyEngine.computeBevelStrain(
            profile: youngMale, rhrBpm: 56.0, hrZoneMinutes: [10, 20, 15, 0, 0], workouts: [workout], activeKcal: 450
        ))
        let olderStrain = try XCTUnwrap(WhoopPhysiologyEngine.computeBevelStrain(
            profile: olderFemale, rhrBpm: 56.0, hrZoneMinutes: [10, 20, 15, 0, 0], workouts: [workout], activeKcal: 450
        ))
        XCTAssertGreaterThan(olderStrain.strainPct, youngStrain.strainPct)

        // 3. Identical 42 ms sleeping HRV reflects MUCH stronger autonomic recovery for 64yo than for 19yo!
        let recYoung = try XCTUnwrap(WhoopPhysiologyEngine.computeBevelRecoveryPercent(
            hrvMs: 42.0, rhrBpm: 56.0, respRpm: 15.0, spo2Pct: 97.5, wristTempDeltaC: 0.0,
            lnHrvBaseline: PersonalBaselineStats(mean: log(youngNorms.hrvExpectedMs), sigma: 0.22, count: 5),
            rhrBaseline: PersonalBaselineStats(mean: youngNorms.restingHrExpected, sigma: 3.0, count: 5),
            respBaseline: PersonalBaselineStats(mean: 15.0, sigma: 0.6, count: 5),
            profile: youngMale
        ))
        let recOlder = try XCTUnwrap(WhoopPhysiologyEngine.computeBevelRecoveryPercent(
            hrvMs: 42.0, rhrBpm: 56.0, respRpm: 15.0, spo2Pct: 97.5, wristTempDeltaC: 0.0,
            lnHrvBaseline: PersonalBaselineStats(mean: log(olderNorms.hrvExpectedMs), sigma: 0.22, count: 5),
            rhrBaseline: PersonalBaselineStats(mean: olderNorms.restingHrExpected, sigma: 3.0, count: 5),
            respBaseline: PersonalBaselineStats(mean: 15.0, sigma: 0.6, count: 5),
            profile: olderFemale
        ))
        XCTAssertGreaterThan(recOlder, recYoung + 15)

        // 4. Identical 7h 20m sleep with 12% Deep scores higher for 64yo (meets age deep/duration norm) than 19yo!
        let sleepYoung = WhoopPhysiologyEngine.computeBevelSleepScore(
            asleepMinutes: 440, inBedMinutes: 465, deepMinutes: 53, remMinutes: 88, awakeMinutes: 25, awakeCount: 1,
            hrDipPct: 12.0, targetMinutes: youngNorms.sleepTargetHours * 60.0,
            deepTargetPct: youngNorms.deepTargetPct, remTargetPct: youngNorms.remTargetPct
        )
        let sleepOlder = WhoopPhysiologyEngine.computeBevelSleepScore(
            asleepMinutes: 440, inBedMinutes: 465, deepMinutes: 53, remMinutes: 88, awakeMinutes: 25, awakeCount: 1,
            hrDipPct: 12.0, targetMinutes: olderNorms.sleepTargetHours * 60.0,
            deepTargetPct: olderNorms.deepTargetPct, remTargetPct: olderNorms.remTargetPct
        )
        XCTAssertGreaterThan(sleepOlder, sleepYoung)

        // 5. Optimal effort target ceiling is higher for young recovery than 64yo
        let youngRange = WhoopPhysiologyEngine.optimalTargetRange(for: 80, profile: youngMale)
        let olderRange = WhoopPhysiologyEngine.optimalTargetRange(for: 80, profile: olderFemale)
        XCTAssertGreaterThan(youngRange.upperBound, olderRange.upperBound)

        // 6. Biological age evaluates against each person's OWN cohort norms
        let olderBio = WhoopPhysiologyEngine.computeBiologicalAge(
            profile: olderFemale, meanRhr: 55.0, meanHrv: 42.0, meanSleepHours: 7.6, meanSteps: 8500, vo2Max: 34.0
        )
        XCTAssertLessThan(olderBio.deltaYears, 0.0)

        // 7. Backward-compatible Codable decoding of legacy v1 UserPhysiologyProfile JSON (without lastName/birthDateIso/profilePhotoPath)
        let legacyJson = #"{"userName":"Unai","ageYears":22,"sex":"Hombre","weightKg":70,"heightCm":178,"onboardingCompleted":true}"#
        let decoded = try JSONDecoder().decode(UserPhysiologyProfile.self, from: Data(legacyJson.utf8))
        XCTAssertEqual(decoded.userName, "Unai")
        XCTAssertEqual(decoded.lastName, "")
        XCTAssertNil(decoded.birthDateIso)
        XCTAssertEqual(decoded.profileSetupVersion, 0)
    }

    @MainActor
    func testStoreRecomputesStoredHistoryImmediatelyWhenProfileAgeOrSexChanges() throws {
        let store = ImprovingStore()
        // First-ever launch MUST show onboarding carousel!
        XCTAssertFalse(store.userProfile.onboardingCompleted)

        var day = RealBiometricDaySummary(dateIso: "2026-11-23")
        day.asleepMinutes = 440
        day.inBedMinutes = 465
        day.deepMinutes = 52
        day.remMinutes = 86
        day.hrvMs = 45.0
        day.restingHrBpm = 56.0
        day.activeKcal = 420
        day.hrZoneMinutes = [12, 18, 12, 0, 0]
        store.realHistory = ["2026-11-23": day]
        store.hasImportedOrPairedRealData = true

        var pYoung = UserPhysiologyProfile(userName: "Aitor", lastName: "Test", ageYears: 19, sex: .male, weightKg: 78, heightCm: 185)
        pYoung.birthDateIso = "2007-04-01"
        store.completeOnboarding(pYoung)
        XCTAssertTrue(store.userProfile.onboardingCompleted)
        let rec1 = try XCTUnwrap(store.realHistory["2026-11-23"]?.recoveryPct)
        let strain1 = try XCTUnwrap(store.realHistory["2026-11-23"]?.strainPct)
        let sleep1 = try XCTUnwrap(store.realHistory["2026-11-23"]?.sleepPct)

        var pOlder = UserPhysiologyProfile(userName: "Aitor", lastName: "Test", ageYears: 65, sex: .female, weightKg: 56, heightCm: 158)
        pOlder.birthDateIso = "1961-04-01"
        pOlder.onboardingCompleted = true
        store.updateProfile(pOlder)
        let rec2 = try XCTUnwrap(store.realHistory["2026-11-23"]?.recoveryPct)
        let strain2 = try XCTUnwrap(store.realHistory["2026-11-23"]?.strainPct)
        let sleep2 = try XCTUnwrap(store.realHistory["2026-11-23"]?.sleepPct)

        XCTAssertNotEqual(rec1, rec2)
        XCTAssertGreaterThan(strain2, strain1)
        XCTAssertGreaterThan(sleep2, sleep1)
    }

    func testSleepingHrPreservesRemPeaksAndPersonal60DayBandAdaptsToUserHistory() throws {
        // 1. Sleeping HR with steady ~48 bpm + genuine REM peaks (62..69 bpm) + 1 optical sensor glitch (118 bpm):
        //    Must preserve the REM peaks (~50.1 bpm) while rejecting the 118 bpm glitch!
        let samples: [Double] = [
            47, 48, 48, 48, 49, 48, 47, 48, 48, 49,
            48, 47, 48, 49, 48, 47, 48, 48, 49, 48,
            62, 65, 67, 69, 118
        ]
        let agg = try XCTUnwrap(WhoopPhysiologyEngine.aggregateSleepingHr(samples))
        // Without 118, exact mean of 24 real readings (20 ~48 bpm + 4 REM 62..69) = (960 + 263) / 24 = 50.96 bpm
        // (Old 3*MAD cutoff stripped 62..69 and dropped it to 48.0 bpm!)
        XCTAssertEqual(agg, 51.0, accuracy: 0.25)

        // 2. 60-day personal normal band adapts to user's actual ~56 ms HRV history so 53.7 ms evaluates as Normal (green),
        //    rather than falsely flagging "Bajo" against a generic young-adult ~78 ms population mean!
        let youngProfile = UserPhysiologyProfile(userName: "Aitor", ageYears: 20, sex: .male, weightKg: 70, heightCm: 176)
        let sparseBand = WhoopPhysiologyEngine.computePersonalVitalNormalBand(kind: .hrv, trailingValues: [55, 58], profile: youngProfile)
        XCTAssertFalse(sparseBand.isPersonal)

        let personalHistory: [Double] = [54, 57, 52, 61, 55, 59, 53, 56, 60, 54, 58, 55]
        let personalBand = WhoopPhysiologyEngine.computePersonalVitalNormalBand(kind: .hrv, trailingValues: personalHistory, profile: youngProfile)
        XCTAssertTrue(personalBand.isPersonal)
        let eval = WhoopPhysiologyEngine.evaluateVital(
            value: 53.7,
            bandLow: personalBand.low,
            bandHigh: personalBand.high,
            higherIsBetter: true,
            hasData: true
        )
        XCTAssertEqual(eval.statusLabel, "Normal")
    }

    @MainActor
    func testLiveStressScoreTracksLatestReadingWhileAvgTracksDailyMean() throws {
        let store = ImprovingStore()
        store.hasImportedOrPairedRealData = true
        let todayIso = store.selectedDateIso

        // Simulate realistic day: low sleeping stress (8-12) overnight keeping 24h mean at 23,
        // while the latest evening reading at 21:30 jumps to 68!
        var day = RealBiometricDaySummary(dateIso: todayIso)
        day.restingHrBpm = 49.0
        day.stressScore = 23
        day.stressSamples5m = [
            TimedBiometricPoint(minuteOfDay: 120, value: 8.0, epochSec: nil),
            TimedBiometricPoint(minuteOfDay: 240, value: 10.0, epochSec: nil),
            TimedBiometricPoint(minuteOfDay: 360, value: 12.0, epochSec: nil),
            TimedBiometricPoint(minuteOfDay: 600, value: 24.0, epochSec: nil),
            TimedBiometricPoint(minuteOfDay: 900, value: 30.0, epochSec: nil),
            TimedBiometricPoint(minuteOfDay: 1290, value: 68.0, epochSec: nil)
        ]
        store.realHistory = [todayIso: day]
        store.dayOffset = 0

        // On Today, displayStressScore MUST reflect live latest reading (68), NOT stay frozen at daily average (23)!
        XCTAssertEqual(store.currentStressScore, 68)
        XCTAssertEqual(store.displayStressScore, 68)
        XCTAssertEqual(store.stressAvg, 25)
        XCTAssertEqual(store.stressStatusLabel, "Alto")

        // Merging a fresh partial sync later at 22:00 (value 41) preserves earlier samples & updates live reading!
        var incoming = RealBiometricDaySummary(dateIso: todayIso)
        incoming.stressSamples5m = [
            TimedBiometricPoint(minuteOfDay: 1320, value: 41.0, epochSec: nil)
        ]
        let merged = WhoopExportImporter.mergeDays(existing: [todayIso: day], imported: [todayIso: incoming])
        let mergedDay = try XCTUnwrap(merged[todayIso])
        XCTAssertEqual(mergedDay.stressSamples5m.count, 7)
        XCTAssertEqual(mergedDay.stressSamples5m.last?.minuteOfDay, 1320)
        XCTAssertEqual(Int((mergedDay.stressSamples5m.last?.value ?? 0).rounded()), 41)
    }

    func testShortcutsFitnessWorkoutsVo2DistanceFlightsAndAutoHrrExtraction() throws {
        // Full Shortcuts payload with workouts, VO2 Max, distance, flights climbed, AND intraday HR
        // spanning during the workout (18:00-18:45) + 1 minute post-workout (18:46) for genuine auto-HRR!
        let json = """
        {
          "source": "Atajos de Apple",
          "rhr_values": "50.0",
          "rhr_dates": "23 nov 2026, 6:00",
          "vo2_values": "44,3 mL/kg·min",
          "vo2_dates": "23 nov 2026, 18:45",
          "distance_values": "4,25 km",
          "distance_dates": "23 nov 2026, 18:45",
          "cycling_distance_values": "12,80 km",
          "cycling_distance_dates": "23 nov 2026, 18:45",
          "flights_values": "12",
          "flights_dates": "23 nov 2026, 18:45",
          "workout_names": "Entrenamiento de fuerza tradicional\\nBici al aire libre",
          "workout_starts": "23 nov 2026, 18:00\\n23 nov 2026, 19:00",
          "workout_ends": "23 nov 2026, 18:45\\n23 nov 2026, 19:40",
          "workout_durations": "45\\n40",
          "workout_kcals": "320 kcal\\n380 kcal",
          "hr_values": "118\\n142\\n154\\n160\\n132\\n126\\n148\\n152\\n124",
          "hr_dates": "23 nov 2026, 18:05\\n23 nov 2026, 18:15\\n23 nov 2026, 18:30\\n23 nov 2026, 18:44\\n23 nov 2026, 18:46\\n23 nov 2026, 19:10\\n23 nov 2026, 19:25\\n23 nov 2026, 19:39\\n23 nov 2026, 19:41"
        }
        """
        let res = ShortcutsHealthSyncImporter.parseData(try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertNil(res.errorMessage)
        let day = try XCTUnwrap(res.days["2026-11-23"])

        XCTAssertEqual(day.vo2MaxMlKgMin ?? 0, 44.3, accuracy: 0.1)
        XCTAssertEqual(day.distanceKm ?? 0, 17.05, accuracy: 0.1)
        // 12 flights * 3.05m = 36.6m
        XCTAssertEqual(day.elevationM ?? 0, 36.6, accuracy: 0.5)
        XCTAssertEqual(day.workouts.count, 2)
        XCTAssertEqual(day.workouts.first?.title, "Entrenamiento de fuerza tradicional")
        XCTAssertEqual(day.workouts.first?.kcal, 320)
        // Enriched from intraday HR samples: average HR & 6-zone array populated!
        XCTAssertGreaterThan(day.workouts.first?.avgHrBpm ?? 0, 120)
        XCTAssertEqual(day.workouts.first?.hrZoneMinutes6?.count, 6)
        // Auto-computed 1-min post-workout HRR: 160 -> 132 = 28 ppm & 152 -> 124 = 28 ppm!
        let autoHrr = try XCTUnwrap(day.hrRecoveryBpm)
        XCTAssertEqual(autoHrr, 28.0, accuracy: 2.0)
    }

    @MainActor
    func testEwmaTrainingLoadVo2StandardizationTrendsMuscleFreshnessAndRoutines() throws {
        let store = ImprovingStore()
        store.hasImportedOrPairedRealData = true
        let profile = UserPhysiologyProfile(userName: "Unai", ageYears: 22, sex: .male, weightKg: 72, heightCm: 178)
        store.userProfile = profile

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var hist: [String: RealBiometricDaySummary] = [:]
        for back in 0..<26 {
            let dt = cal.date(byAdding: .day, value: -back, to: today)!
            let iso = store.isoFormatter.string(from: dt)
            var d = RealBiometricDaySummary(dateIso: iso)
            d.vo2MaxMlKgMin = 42.5 + Double(26 - back) * 0.08
            d.hrRecoveryBpm = 27.0 + Double(back % 4)
            d.strainPct = back % 2 == 0 ? 48 : 22
            if back % 2 == 0 {
                d.workouts = [
                    EffortEventItem(
                        id: "w_\(back)",
                        title: back % 4 == 0 ? "Entrenamiento de fuerza tradicional" : "Bici al aire libre",
                        timeRange: "18:00 - 18:45",
                        durationMin: 45,
                        avgHrBpm: 138,
                        strainScore: 10.5,
                        strainPct: 42,
                        categoryLabel: back % 4 == 0 ? "Fuerza" : "Cardio",
                        kcal: 340,
                        distanceKm: back % 4 == 0 ? nil : 16.5,
                        dateIso: iso,
                        hrZoneMinutes6: [4, 15, 16, 8, 2, 0]
                    )
                ]
            }
            hist[iso] = d
        }
        store.realHistory = hist
        store.dayOffset = 0

        // 1. Cardio & Muscular EWMA load + breakdown sums to exact span (31 days)
        let cardio = store.trainingLoadAnalysis(tab: .cardio, spanDays: 31, windowPageOffset: 0)
        XCTAssertTrue(cardio.hasAnyData)
        XCTAssertEqual(cardio.breakdown.count, 7)
        XCTAssertEqual(cardio.breakdown.reduce(0) { $0 + $1.days }, 31)
        XCTAssertLessThanOrEqual(cardio.optimalLow, cardio.optimalHigh)

        let muscular = store.trainingLoadAnalysis(tab: .muscular, spanDays: 31, windowPageOffset: 0)
        XCTAssertEqual(muscular.breakdown.count, 6)
        XCTAssertEqual(muscular.breakdown.reduce(0) { $0 + $1.days }, 31)

        // 2. Standardized 5-segment VO2 Max & HRR bands
        let vo2Eval = WhoopPhysiologyEngine.standardizeVo2Max(44.3, profile: profile)
        XCTAssertEqual(vo2Eval.labels.count, 5)
        XCTAssertEqual(vo2Eval.categoryTitle, "Aceptable")

        let hrrEval = WhoopPhysiologyEngine.standardizeHrRecovery(27.0, profile: profile)
        XCTAssertEqual(hrrEval.labels.count, 5)
        XCTAssertEqual(hrrEval.categoryTitle, "Aceptable")

        // 3. Multi-period rolling-7d Trend Analysis rows (3d / 7d / 14d / 30d / 90d)
        let trends = WhoopPhysiologyEngine.computeMultiPeriodTrendRows(history: hist, anchorDate: today) { $0.vo2MaxMlKgMin }
        XCTAssertEqual(trends.map(\.label), ["3 día(s)", "7 día(s)", "14 día(s)", "30 día(s)", "90 día(s)"])
        XCTAssertGreaterThan(trends[1].delta ?? -99, 0.0)

        // 4. Routines + Strength Logger + 20-Muscle Freshness Decay
        let routine = WorkoutRoutineTemplate(
            id: "r_push", name: "Empuje", category: "Fuerza",
            iconName: "figure.strengthtraining.traditional", isPinned: true,
            exercises: [
                WorkoutRoutineExercise(
                    id: "ex1", name: "Press banca", targetSets: 4, targetReps: 10, defaultWeightKg: 60,
                    primaryMuscles: [.pectorales], secondaryMuscles: [.triceps, .hombros]
                )
            ]
        )
        store.saveRoutine(routine)
        XCTAssertEqual(store.workoutRoutines.count, 1)
        store.toggleRoutinePin("r_push")
        XCTAssertFalse(store.workoutRoutines.first?.isPinned ?? true)

        let todaySets = (0..<6).map { idx in
            StrengthLoggedSet(
                id: "s_\(idx)", dateIso: store.selectedDateIso, exercise: "Press banca",
                reps: 10, weightKg: 65, primaryMuscles: [.pectorales], secondaryMuscles: [.triceps], completed: true
            )
        }
        store.logCompletedStrengthSession(title: "Empuje", durationMin: 50, kcal: 310, sets: todaySets)
        let snaps = store.muscleGroupSnapshots(for: today)
        XCTAssertEqual(snaps.count, MuscleGroupKind.allCases.count)
        let pecs = try XCTUnwrap(snaps.first(where: { $0.muscle == .pectorales }))
        XCTAssertTrue(pecs.state == .fatigued || pecs.state == .exhausted)
        XCTAssertLessThan(pecs.freshnessPct, 80)
    }

    @MainActor
    func testGeminiApiKeySanitizationAndSupportedModels() {
        XCTAssertEqual(GeminiCoachService.sanitizeApiKey("  \"Bearer AIzaSyTestKey123 \" \n"), "AIzaSyTestKey123")
        XCTAssertEqual(GeminiCoachService.sanitizeApiKey("'AIzaSyClean456'"), "AIzaSyClean456")
        XCTAssertEqual(GeminiCoachService.supportedModels.first, "auto")
        XCTAssertTrue(GeminiCoachService.supportedModels.contains("gemini-3.1-flash-lite"))
        XCTAssertTrue(GeminiCoachService.supportedModels.contains("gemini-flash-latest"))

        // Auto-discovery ranking filters out embedding/tts/imagen/gemma and prioritizes newest active Flash models!
        let ranked = GeminiCoachService.rankDiscoveredModels([
            ("models/text-embedding-004", ["embedContent"]),
            ("models/gemini-2.5-flash-tts", ["generateContent"]),
            ("models/gemma-3-27b-it", ["generateContent"]),
            ("models/gemini-2.5-flash", ["generateContent"]),
            ("models/gemini-3.1-flash-lite", ["generateContent"]),
            ("models/gemini-3.5-flash-lite", ["generateContent"]),
            ("models/imagen-3.0-generate-002", ["generateContent"]),
        ])
        XCTAssertEqual(ranked.first, "gemini-3.5-flash-lite")
        XCTAssertEqual(ranked.dropFirst().first, "gemini-3.1-flash-lite")
        XCTAssertFalse(ranked.contains(where: { $0.contains("tts") || $0.contains("embedding") || $0.contains("gemma") || $0.contains("imagen") }))

        // Trend extractors map every Esfuerzo / Recuperación / Sueño / Estrés trend ID to its OWN real metric (never HRV!)
        let store = ImprovingStore()
        var day = RealBiometricDaySummary(dateIso: "2026-11-24")
        day.strainPct = 44
        day.recoveryPct = 78
        day.sleepPct = 94
        day.remMinutes = 110
        day.deepMinutes = 85
        day.stepsCount = 8200
        day.stressScore = 31
        XCTAssertEqual(store.trendExtractor(for: "t_strain")(day), 44)
        XCTAssertEqual(store.trendExtractor(for: "t_steps")(day), 8200)
        XCTAssertEqual(store.trendExtractor(for: "r_rec")(day), 78)
        XCTAssertEqual(store.trendExtractor(for: "s_score")(day), 94)
        XCTAssertEqual(store.trendExtractor(for: "s_rem")(day), 110)
        XCTAssertEqual(store.trendExtractor(for: "s_deep")(day), 85)
        XCTAssertEqual(store.trendExtractor(for: "st_score")(day), 31)
    }

    @MainActor
    func testShortcutsLatestFirstOrderSpanishAmPmDatesAndInPlaceFileOverwriteSignature() throws {
        // 1. Reverse-chronological (Latest First) Shortcuts JSON with Spanish 12h "a. m." / "p. m." + 24h dates
        let json = """
        {
          "generated_at": "24 nov 2026, 11:25",
          "rhr_values": "49.5\\n50.0",
          "rhr_dates": "24 nov 2026, 6:30\\n23 nov 2026, 6:30",
          "hr_values": "88\\n76\\n54\\n52",
          "hr_dates": "24 nov. 2026, 11:20 a. m.\\n24 nov 2026, 9:05 a. m.\\n23 nov 2026, 1:15 p. m.\\n23 nov 2026, 1:05 a. m."
        }
        """
        let res = ShortcutsHealthSyncImporter.parseData(try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertNil(res.errorMessage)
        let today = try XCTUnwrap(res.days["2026-11-24"])
        let yesterday = try XCTUnwrap(res.days["2026-11-23"])

        // Today's latest 5-min bucket MUST be 11:20 (minute 680) even though Shortcut sent Latest First!
        XCTAssertEqual(today.stressSamples5m.last?.minuteOfDay, 680)
        // Yesterday's "1:15 p. m." MUST parse as 13:15 (minute 795), NOT 01:15!
        XCTAssertEqual(yesterday.stressSamples5m.last?.minuteOfDay, 795)

        let tag = ImprovingStore.formatLatestReadingTag(from: res.days)
        XCTAssertTrue(tag.contains("11:20"), "Expected latest reading tag to contain 11:20, got: \(tag)")

        // 2. Uncached kernel stat signature MUST change immediately upon in-place overwrite of health_sync.json!
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test_health_sync_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("{\"hr_values\":\"60\"}".utf8).write(to: tmp, options: .atomic)
        let sig1 = ShortcutsHealthSyncImporter.fileSignature(for: tmp)
        try Data("{\"hr_values\":\"60\\n84\"}".utf8).write(to: tmp, options: .atomic)
        let sig2 = ShortcutsHealthSyncImporter.fileSignature(for: tmp)
        XCTAssertNotEqual(sig1, sig2)
    }

    @MainActor
    func testLowPowerModeSleepRechargesBodyBatteryAndKeepsRecoveryRealistic() throws {
        // Prior day ended at 28.0% energy at 23:45 (typical evening battery before bed)
        var prior: [String: RealBiometricDaySummary] = [:]
        prior["2026-11-23"] = RealBiometricDaySummary(
            dateIso: "2026-11-23",
            restingHrBpm: 50.0,
            hrvMs: 68.0,
            energyBankPercent: 28,
            energySamples5m: [TimedBiometricPoint(minuteOfDay: 1425, value: 28.0, epochSec: nil)]
        )

        // Scenario 1: Apple Watch Low Power Mode overnight -> 8h sleep (94%+ score), ZERO HR readings during sleep,
        // ZERO overnight HRV & RHR; daytime HR only resumes after waking up (09:00 & 11:30)!
        let envZeroOvernightHr = ShortcutsSyncEnvelope(
            source: "Atajos de Apple",
            hrValues: ["72 lat/min", "78 lat/min"],
            hrDates: ["24/11/2026, 9:00", "24/11/2026, 11:30"],
            sleepValues: ["Dormido (Profundo)", "Dormido (REM)", "Dormido (Esencial)"],
            sleepStarts: ["24/11/2026, 0:30", "24/11/2026, 2:00", "24/11/2026, 3:45"],
            sleepEnds: ["24/11/2026, 2:00", "24/11/2026, 3:45", "24/11/2026, 8:30"]
        )
        let res1 = ShortcutsHealthSyncImporter.parseEnvelope(envZeroOvernightHr, priorHistory: prior)
        XCTAssertNil(res1.errorMessage)
        let day1 = try XCTUnwrap(res1.days["2026-11-24"])
        XCTAssertGreaterThanOrEqual(day1.sleepPct ?? 0, 90)
        // Must NEVER fabricate raw HRV or RHR sensors when Watch Low Power Mode skipped them!
        XCTAssertNil(day1.hrvMs)
        XCTAssertNil(day1.restingHrBpm)
        // Recovery % still functions realistically from real sleep quality!
        let lpmRec = try XCTUnwrap(day1.recoveryPct)
        XCTAssertTrue((65...92).contains(lpmRec), "Expected realistic Low Power Mode recovery (65..92), got \(lpmRec)")
        // Energy starts continuously at prior day's 28.0% and recharges >= +50% across the 8h sleep (NOT +4%!)
        let startE1 = try XCTUnwrap(day1.energySamples5m.first?.value)
        let peakE1 = try XCTUnwrap(day1.energySamples5m.map(\.value).max())
        XCTAssertEqual(startE1, 28.0, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(peakE1, 82.0, "Expected peak energy >= 82% after 8h 94% sleep, got \(peakE1)")
        XCTAssertGreaterThanOrEqual(peakE1 - startE1, 52.0, "Expected overnight charge >= +52%, got \(peakE1 - startE1)")

        // Scenario 2: 1 sparse HR sample before sleep (00:30) and 1 near wake-up (07:50) -> old min(dt, 45) capped this at +4%!
        let envSparseHr = ShortcutsSyncEnvelope(
            source: "Atajos de Apple",
            hrValues: ["54 lat/min", "52 lat/min", "74 lat/min"],
            hrDates: ["24/11/2026, 0:30", "24/11/2026, 7:50", "24/11/2026, 11:00"],
            sleepValues: ["Dormido"],
            sleepStarts: ["24/11/2026, 0:30"],
            sleepEnds: ["24/11/2026, 8:30"]
        )
        let res2 = ShortcutsHealthSyncImporter.parseEnvelope(envSparseHr, priorHistory: prior)
        let day2 = try XCTUnwrap(res2.days["2026-11-24"])
        let startE2 = try XCTUnwrap(day2.energySamples5m.first?.value)
        let peakE2 = try XCTUnwrap(day2.energySamples5m.map(\.value).max())
        XCTAssertEqual(startE2, 28.0, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(peakE2 - startE2, 52.0, "Sparse HR during 8h sleep must recharge >= +52%, not +4%!")

        // Scenario 3: Woke up from Low Power Mode sleep before ANY daytime HR sample was logged yet
        let envSleepOnly = ShortcutsSyncEnvelope(
            source: "Atajos de Apple",
            sleepValues: ["Dormido"],
            sleepStarts: ["24/11/2026, 0:30"],
            sleepEnds: ["24/11/2026, 8:30"]
        )
        let res3 = ShortcutsHealthSyncImporter.parseEnvelope(envSleepOnly, priorHistory: prior)
        let day3 = try XCTUnwrap(res3.days["2026-11-24"])
        XCTAssertGreaterThanOrEqual(day3.energyBankPercent ?? 0, 82)
        XCTAssertNotNil(day3.recoveryPct)

        // Scenario 4: Retroactive store recompute heals an already-persisted +4% day to full physiological recharge
        let store = ImprovingStore()
        store.hasImportedOrPairedRealData = true
        var buggyToday = day1
        buggyToday.energySamples5m = [
            TimedBiometricPoint(minuteOfDay: 30, value: 28.0, epochSec: nil),
            TimedBiometricPoint(minuteOfDay: 470, value: 32.0, epochSec: nil)
        ]
        buggyToday.energyBankPercent = 32
        store.realHistory = ["2026-11-23": prior["2026-11-23"]!, "2026-11-24": buggyToday]
        store.recomputeMetricsForCurrentProfile()
        let healed = try XCTUnwrap(store.realHistory["2026-11-24"])
        let healedPeak = try XCTUnwrap(healed.energySamples5m.map(\.value).max())
        XCTAssertGreaterThanOrEqual(healedPeak, 82.0)
    }

    @MainActor
    func testDirectUrlEncodedDataPayloadSyncsWithoutPasteboard() throws {
        let store = ImprovingStore()
        let json = #"{"rhr_values":"48.0","rhr_dates":"24 nov 2026, 06:00","hr_values":"74","hr_dates":"24 nov 2026, 18:10"}"#
        var comps = URLComponents()
        comps.scheme = "improving"
        comps.host = "sync"
        comps.queryItems = [URLQueryItem(name: "data", value: json)]
        let url = try XCTUnwrap(comps.url)
        store.handleIncomingURL(url)
        let exp = expectation(description: "Direct URL payload processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(store.realHistory["2026-11-24"]?.restingHrBpm ?? 0, 48.0, accuracy: 0.1)
    }

    func testMasterShortcutsPayloadParsesAll18MetricsAndAutoDetectsRealHrExerciseBoutWithHrr() throws {
        // Simulates the EXACT JSON emitted by the single unified `Sync Improving` shortcut (no invalid Workouts action!):
        // Includes all 18 native Apple Shortcuts metrics + a real 30-min elevated-HR session (18:00-18:30) and 1-min cool-down (18:31).
        let json = """
        {
          "generated_at": "24 nov 2026, 19:00",
          "hr_values": "132\\n160\\n156\\n150\\n146\\n142\\n138\\n136\\n130\\n72\\n50",
          "hr_dates": "24 nov 2026, 18:31\\n24 nov 2026, 18:30\\n24 nov 2026, 18:26\\n24 nov 2026, 18:22\\n24 nov 2026, 18:18\\n24 nov 2026, 18:14\\n24 nov 2026, 18:09\\n24 nov 2026, 18:04\\n24 nov 2026, 18:00\\n24 nov 2026, 12:00\\n24 nov 2026, 04:00",
          "hrv_values": "64,5 ms",
          "hrv_dates": "24 nov 2026, 04:30",
          "rhr_values": "49,0",
          "rhr_dates": "24 nov 2026, 06:00",
          "resp_values": "14,8",
          "resp_dates": "24 nov 2026, 04:00",
          "spo2_values": "98 %",
          "spo2_dates": "24 nov 2026, 04:15",
          "temp_values": "36,4 °C",
          "temp_dates": "24 nov 2026, 06:15",
          "sleep_values": "Dormido (Profundo)\\nDormido (REM)\\nDormido (Esencial)",
          "sleep_starts": "24 nov 2026, 00:30\\n24 nov 2026, 02:00\\n24 nov 2026, 03:45",
          "sleep_ends": "24 nov 2026, 02:00\\n24 nov 2026, 03:45\\n24 nov 2026, 08:15",
          "steps_values": "9.420 pasos",
          "steps_dates": "24 nov 2026, 19:00",
          "kcal_values": "610 kcal",
          "kcal_dates": "24 nov 2026, 19:00",
          "vo2_values": "46,2",
          "vo2_dates": "24 nov 2026, 18:35",
          "distance_values": "5,4 km",
          "distance_dates": "24 nov 2026, 19:00",
          "cycling_distance_values": "10,0 km",
          "cycling_distance_dates": "24 nov 2026, 19:00",
          "swimming_distance_values": "1000 m",
          "swimming_distance_dates": "24 nov 2026, 19:00",
          "flights_values": "10",
          "flights_dates": "24 nov 2026, 19:00",
          "weight_values": "71,5 kg",
          "weight_dates": "24 nov 2026, 08:20",
          "body_fat_values": "13,4 %",
          "body_fat_dates": "24 nov 2026, 08:20",
          "lean_mass_values": "61,9 kg",
          "lean_mass_dates": "24 nov 2026, 08:20",
          "glucose_values": "89 mg/dL",
          "glucose_dates": "24 nov 2026, 08:25"
        }
        """
        let res = ShortcutsHealthSyncImporter.parseData(try XCTUnwrap(json.data(using: .utf8)))
        XCTAssertNil(res.errorMessage)
        let day = try XCTUnwrap(res.days["2026-11-24"])

        // All 18 metrics populated from real values!
        XCTAssertEqual(day.hrvMs ?? 0, 64.5, accuracy: 0.2)
        XCTAssertEqual(day.restingHrBpm ?? 0, 49.0, accuracy: 0.2)
        XCTAssertEqual(day.respRateRpm ?? 0, 14.8, accuracy: 0.2)
        XCTAssertEqual(day.spo2Percent ?? 0, 98.0, accuracy: 0.2)
        XCTAssertEqual(day.wristTempAbsoluteC ?? 0, 36.4, accuracy: 0.2)
        XCTAssertEqual(day.stepsCount, 9420)
        XCTAssertEqual(day.activeKcal, 610)
        XCTAssertEqual(day.vo2MaxMlKgMin ?? 0, 46.2, accuracy: 0.1)
        // 5.4 + 10.0 + 1.0 (1000 m swim) = 16.4 km!
        XCTAssertEqual(day.distanceKm ?? 0, 16.4, accuracy: 0.2)
        // 10 flights * 3.05m = 30.5 m
        XCTAssertEqual(day.elevationM ?? 0, 30.5, accuracy: 0.5)
        XCTAssertEqual(day.bodyWeightKg ?? 0, 71.5, accuracy: 0.1)
        XCTAssertEqual(day.bodyFatPct ?? 0, 13.4, accuracy: 0.1)
        XCTAssertEqual(day.leanMassKg ?? 0, 61.9, accuracy: 0.1)
        XCTAssertEqual(day.glucoseMgDl, 89)
        XCTAssertGreaterThanOrEqual(day.sleepPct ?? 0, 88)

        // Real 30-min elevated-HR workout bout (18:00-18:30) auto-detected + 1-min post-bout HRR (160 -> 132 = 28 ppm)!
        let autoWk = try XCTUnwrap(day.workouts.first)
        XCTAssertEqual(autoWk.durationMin, 30)
        XCTAssertGreaterThanOrEqual(autoWk.avgHrBpm, 140)
        XCTAssertEqual(autoWk.hrZoneMinutes6?.count, 6)
        let hrr = try XCTUnwrap(day.hrRecoveryBpm)
        XCTAssertEqual(hrr, 28.0, accuracy: 2.0)
    }

    func testMultimodalNutritionJsonParserAndLocalSpanishFoodFallback() throws {
        let geminiJson = """
        ```json
        {
          "title": "Huevos revueltos con tostada y aguacate",
          "kcal": 510,
          "protein_g": 24,
          "carbs_g": 34,
          "fat_g": 31,
          "caffeine_mg": 80,
          "alcohol_drinks": 0,
          "calcium_mg": 95,
          "quality_score": 91,
          "summary": "Desayuno denso en proteína completa, grasas monoinsaturadas y fibra."
        }
        ```
        """
        let parsed = try XCTUnwrap(GeminiCoachService.parseMealEstimateJson(geminiJson, usedLiveAI: true, modelUsed: "gemini-3-flash"))
        XCTAssertEqual(parsed.title, "Huevos revueltos con tostada y aguacate")
        XCTAssertEqual(parsed.kcal, 510)
        XCTAssertEqual(parsed.proteinG, 24)
        XCTAssertEqual(parsed.carbsG, 34)
        XCTAssertEqual(parsed.fatG, 31)
        XCTAssertEqual(parsed.caffeineMg, 80, accuracy: 0.1)
        XCTAssertEqual(parsed.qualityScore, 91)
        XCTAssertTrue(parsed.usedLiveAI)

        let offlineEst = GeminiCoachService.estimateMealLocally(from: "2 huevos revueltos con tostada y aguacate y un café", hasPhoto: false)
        XCTAssertGreaterThan(offlineEst.kcal, 380)
        XCTAssertGreaterThanOrEqual(offlineEst.proteinG, 16)
        XCTAssertGreaterThanOrEqual(offlineEst.caffeineMg, 75)
        XCTAssertGreaterThanOrEqual(offlineEst.qualityScore, 80)
    }

    @MainActor
    func testPersistedMealsEditDeleteAndManualNutrients() throws {
        let store = ImprovingStore()
        store.mealsByDate = [:]
        store.hydrationGlassesByDate = [:]
        store.manualNutrientsByDate = [:]

        let meal = NutritionMealItem(
            id: "meal_test_1",
            title: "Salmón con arroz",
            timeLabel: "14:20",
            kcal: 640,
            proteinG: 44,
            carbsG: 52,
            fatG: 24,
            qualityScore: 92,
            caffeineMg: 75,
            alcoholDrinks: nil,
            calciumMg: 60
        )
        store.saveMeal(meal)
        XCTAssertEqual(store.mealsToday.count, 1)
        XCTAssertEqual(store.totalCaloriesToday, 640)
        XCTAssertEqual(store.totalProteinToday, 44)
        XCTAssertEqual(store.foodQualityScore, 92)

        // Add manual caffeine + custom hydration ml and verify persistence across calculations
        store.addNutrientAmount(key: "Cafeína", amount: 50)
        store.addNutrientAmount(key: "Hidratación", amount: 330)
        XCTAssertEqual(store.totalCaffeineTodayMg, 125, accuracy: 0.1)
        XCTAssertEqual(store.totalHydrationTodayMl, 330, accuracy: 0.1)

        // Edit meal in place
        var edited = meal
        edited.kcal = 700
        edited.proteinG = 50
        store.saveMeal(edited)
        XCTAssertEqual(store.mealsToday.count, 1)
        XCTAssertEqual(store.totalCaloriesToday, 700)
        XCTAssertEqual(store.totalProteinToday, 50)

        // Delete meal
        store.deleteMeal(id: "meal_test_1")
        XCTAssertTrue(store.mealsToday.isEmpty)
        XCTAssertEqual(store.totalCaffeineTodayMg, 50, accuracy: 0.1)
    }

    @MainActor
    func testCustomizableDiarioHabitsAndDailyNotePersistence() throws {
        let store = ImprovingStore()
        store.hiddenJournalHabitIds = []
        store.customJournalHabits = []
        store.journalNotesByDate = [:]

        store.addCustomJournalHabit(emoji: "📚", title: "Exámenes UPV", isNightHabit: false)
        XCTAssertEqual(store.customJournalHabits.count, 1)
        let customId = try XCTUnwrap(store.customJournalHabits.first?.id)

        store.setJournalCheck(habitId: customId, state: .yes)
        store.setJournalNote("Día intenso de examen y poco descanso previo")
        XCTAssertEqual(store.journalNote(), "Día intenso de examen y poco descanso previo")
        XCTAssertTrue(store.hasAnyJournalActivity(for: store.selectedDateIso))

        // Hide 18 built-in habits -> requiredManualCountForCompletion adapts dynamically so day remains completable!
        for hid in ImprovingStore.manualHabitIds.prefix(20) {
            store.toggleHabitHidden(hid)
        }
        XCTAssertLessThan(store.requiredManualCountForCompletion, 20)
        store.resetHiddenHabits()
        store.deleteCustomJournalHabit(id: customId)
        store.setJournalNote("")
    }

    func testSmartNotificationSleepPlanCalculation() {
        // Wake at 07:30 (450m), need 8h 25m (505m), lead 30m -> Bedtime 23:05, Notify 22:35!
        let plan = LocalNotificationManager.computeSleepNotificationPlan(
            wakeHour: 7,
            wakeMinute: 30,
            sleepNeedMinutes: 505,
            leadMinutes: 30
        )
        XCTAssertEqual(plan.wakeLabel, "07:30")
        XCTAssertEqual(plan.bedtimeLabel, "23:05")
        XCTAssertEqual(plan.notifyLabel, "22:35")
        XCTAssertEqual(plan.sleepNeedLabel, "8 h 25 min")
    }

    @MainActor
    func testIndividualWorkoutEditDeleteAndShareCardPayload() throws {
        let store = ImprovingStore()
        store.hasImportedOrPairedRealData = true
        let iso = store.selectedDateIso
        let initialWk = EffortEventItem(
            id: "wk_1",
            title: "Carrera",
            timeRange: "18:00 - 18:40",
            durationMin: 40,
            avgHrBpm: 152,
            strainScore: 11.4,
            strainPct: 54,
            categoryLabel: "Cardio",
            kcal: 460,
            distanceKm: 7.5,
            dateIso: iso
        )
        store.realHistory[iso] = RealBiometricDaySummary(dateIso: iso, workouts: [initialWk])

        // Share card payload reflects real workout figures
        let card = ShareCardPayload.build(for: .workout(initialWk), store: store)
        XCTAssertEqual(card.title, "Carrera")
        XCTAssertEqual(card.metrics.count, 4)

        // Update workout duration & title -> recalculates strain & persists
        var edited = initialWk
        edited = EffortEventItem(
            id: initialWk.id,
            title: "Series en pista",
            timeRange: "18:00 - 19:00",
            durationMin: 60,
            avgHrBpm: 164,
            strainScore: initialWk.strainScore,
            strainPct: initialWk.strainPct,
            categoryLabel: "Carrera",
            kcal: 680,
            distanceKm: 11.2,
            dateIso: iso
        )
        store.updateWorkout(edited, originalDateIso: iso)
        let updatedWk = try XCTUnwrap(store.workoutsToday.first)
        XCTAssertEqual(updatedWk.title, "Series en pista")
        XCTAssertGreaterThan(updatedWk.strainScore, initialWk.strainScore)

        // Delete workout
        store.deleteWorkout(id: "wk_1", dateIso: iso)
        XCTAssertTrue(store.workoutsToday.isEmpty)
    }

    @MainActor
    func testNutritionQualityFactorsNetEnergyLibraryAndCustomGoals() throws {
        // 1. Gemini 11-factor JSON parsing
        let richJson = """
        {
          "title": "Galletas de avena con chispas de chocolate",
          "emoji": "🍪",
          "kcal": 310,
          "protein_g": 5,
          "carbs_g": 33,
          "fat_g": 18,
          "caffeine_mg": 10,
          "alcohol_drinks": 0,
          "calcium_mg": 35,
          "quality_score": 44,
          "factors": {
            "whole_grains": 2.0,
            "excess_sugar": -8.2,
            "excess_sodium": 0,
            "vegetables": 0,
            "healthy_fats": 0,
            "fruit": 0,
            "nuts_legumes": 0,
            "omega3": 0,
            "red_meat": 0,
            "processed_meat": 0,
            "alcohol": 0
          },
          "summary": "Aporta cereales integrales de la avena pero supera el umbral seguro de azúcar."
        }
        """
        let est = try XCTUnwrap(GeminiCoachService.parseMealEstimateJson(richJson, usedLiveAI: true, modelUsed: "gemini-3-flash"))
        XCTAssertEqual(est.emoji, "🍪")
        XCTAssertEqual(est.qualityFactors.wholeGrains, 2.0, accuracy: 0.01)
        XCTAssertEqual(est.qualityFactors.excessSugar, -8.2, accuracy: 0.01)

        // 2. Store daily factors, Net Energy, Mis Alimentos library & Custom Goals
        let store = ImprovingStore()
        store.mealsByDate = [:]
        store.savedFoodsLibrary = []
        store.customNutritionGoals = CustomNutritionGoals()
        let iso = store.selectedDateIso

        let meal = NutritionMealItem(
            id: "nut_factor_1",
            title: est.title,
            timeLabel: "12:27",
            kcal: est.kcal,
            proteinG: est.proteinG,
            carbsG: est.carbsG,
            fatG: est.fatG,
            qualityScore: est.qualityScore,
            emoji: est.emoji,
            qualityFactors: est.qualityFactors
        )
        store.saveMeal(meal)
        let aggFactors = store.dailyFoodQualityFactors(for: iso)
        XCTAssertEqual(aggFactors.wholeGrains, 2.0, accuracy: 0.01)
        XCTAssertEqual(aggFactors.excessSugar, -8.2, accuracy: 0.01)

        // Net energy = consumed - burned (deficit when only 310 kcal consumed!)
        let net = store.netEnergyKcal(for: iso)
        XCTAssertEqual(net.consumed, 310)
        XCTAssertGreaterThan(net.burned, 1000)
        XCTAssertLessThan(net.net, 0)

        // Favorite library & 1-tap log
        store.toggleMealFavorite(meal)
        XCTAssertEqual(store.savedFoodsCounts.favorites, 1)
        if let libItem = store.savedFoodsLibrary.first {
            store.logLibraryFoodToday(libItem)
            XCTAssertEqual(store.mealsToday.count, 2)
        }

        // Custom nutrition goals override + restore
        store.updateNutritionGoals(CustomNutritionGoals(caloriesKcal: 2400, fatG: 75, carbsG: 260, proteinG: 170))
        XCTAssertEqual(store.effectiveNutritionGoals.kcal, 2400)
        XCTAssertEqual(store.effectiveNutritionGoals.proteinG, 170)

        // Cleanup persisted test artifacts
        store.mealsByDate = [:]
        store.savedFoodsLibrary = []
        store.updateNutritionGoals(CustomNutritionGoals())
        store.flushPersistenceNow()
    }

    func testOpenFoodFactsBarcodeParsingAndGramScaling() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "8410076472106",
            "product_name_es": "Yogur natural proteico",
            "brands": "Hacendado, Mercadona",
            "serving_size": "125 g",
            "serving_quantity": 125,
            "nutriscore_grade": "a",
            "nova_group": 1,
            "nutriments": {
              "energy-kcal_100g": 62,
              "proteins_100g": 10.0,
              "carbohydrates_100g": 4.0,
              "fat_100g": 0.4,
              "sugars_100g": 3.8,
              "salt_100g": 0.12,
              "calcium_100g": 0.14
            }
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let prod = try XCTUnwrap(OpenFoodFactsService.parseOpenFoodFactsResponse(data, fallbackBarcode: "8410076472106"))
        XCTAssertEqual(prod.productName, "Yogur natural proteico")
        XCTAssertEqual(prod.brand, "Hacendado")
        XCTAssertEqual(prod.defaultGrams, 125.0, accuracy: 0.1)

        let est200 = prod.toMealEstimate(grams: 200.0)
        XCTAssertEqual(est200.kcal, 124)
        XCTAssertEqual(est200.proteinG, 20)
        XCTAssertEqual(est200.carbsG, 8)
        XCTAssertGreaterThanOrEqual(est200.qualityScore, 90)
        XCTAssertEqual(est200.calciumMg, 280.0, accuracy: 1.0)
    }

    func testGeminiLabReportJsonParsingAndLocalPdfExtractor() throws {
        let raw = """
        ```json
        {
          "title": "Analítica Synlab",
          "date_iso": "2026-11-20",
          "summary": "Buen perfil lipídico con vitamina D algo justa.",
          "biomarkers": [
            {"name": "Vitamina D (25-OH)", "value": 27.5, "unit": "ng/mL", "ref_min": 30, "ref_max": 100, "optimal_min": 40, "optimal_max": 70, "status": "low", "category": "Vitaminas"},
            {"name": "Glucosa", "value": 84, "unit": "mg/dL", "ref_min": 70, "ref_max": 100, "optimal_min": 72, "optimal_max": 90, "status": "optimal", "category": "Metabolismo"}
          ]
        }
        ```
        """
        let rep = try XCTUnwrap(GeminiCoachService.parseLabReportJson(raw, sourceLabel: "Gemini"))
        XCTAssertEqual(rep.title, "Analítica Synlab")
        XCTAssertEqual(rep.dateIso, "2026-11-20")
        XCTAssertEqual(rep.biomarkers.count, 2)
        XCTAssertEqual(rep.biomarkers[0].status, .low)
        XCTAssertEqual(rep.biomarkers[1].status, .optimal)

        let pdfText = "Resultados Laboratorio: Glucosa 88 mg/dL, Ferritina 92,5 ng/mL, Vitamina D 44 ng/mL, TSH 1,65 uUI/mL"
        let localRep = try XCTUnwrap(GeminiCoachService.parseLabReportFromPlainTextLocally(pdfText))
        XCTAssertGreaterThanOrEqual(localRep.biomarkers.count, 4)
    }

    func testWidgetSnapshotStoreAltStoreGroupResolutionAndWorkoutSportIcons() {
        let altInfo: [String: Any] = [
            "AppGroupIdentifier": "group.com.improving.health.ios",
            "ALTAppGroups": ["group.com.improving.health.ios.9ABC123XYZ"]
        ]
        XCTAssertEqual(WidgetSnapshotStore.resolveSuiteName(infoDictionary: altInfo), "group.com.improving.health.ios.9ABC123XYZ")

        let plainInfo: [String: Any] = ["AppGroupIdentifier": "group.com.improving.health.ios"]
        XCTAssertEqual(WidgetSnapshotStore.resolveSuiteName(infoDictionary: plainInfo), "group.com.improving.health.ios")

        XCTAssertEqual(WorkoutSportStyle.resolve(title: "Partido de fútbol 7", category: "Cardio").icon, "figure.soccer")
        XCTAssertEqual(WorkoutSportStyle.resolve(title: "Pádel con amigos", category: "Cardio").icon, "figure.tennis")
        XCTAssertEqual(WorkoutSportStyle.resolve(title: "Natación piscina", category: "Cardio").icon, "figure.pool.swim")
        XCTAssertEqual(WorkoutSportStyle.resolve(title: "Carrera 10K", category: "Cardio").icon, "figure.run")
    }

    @MainActor
    func testHomeLayoutWeeklyReviewScaleLabsAndCoachPersistenceRoundTrip() throws {
        let store = ImprovingStore()
        store.hasImportedOrPairedRealData = true
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Populate 14 real days for weekly review comparison (recent 7d higher recovery than prev 7d!)
        for back in 0..<14 {
            let dt = cal.date(byAdding: .day, value: -back, to: today)!
            let iso = store.isoFormatter.string(from: dt)
            let isRecent = back < 7
            store.realHistory[iso] = RealBiometricDaySummary(
                dateIso: iso,
                restingHrBpm: isRecent ? 49.0 : 53.0,
                hrvMs: isRecent ? 78.0 : 64.0,
                asleepMinutes: isRecent ? 465 : 420,
                sleepPct: isRecent ? 88 : 76,
                strain21: 12.0,
                strainPct: 58,
                recoveryPct: isRecent ? 82 : 66,
                stepsCount: 9200
            )
        }

        let weekly = store.computeWeeklyReview(anchorDate: today)
        XCTAssertEqual(weekly.daysWithData, 7)
        XCTAssertEqual(weekly.avgRecovery, 82)
        XCTAssertEqual(weekly.recoveryDelta, 16)
        XCTAssertEqual(weekly.avgHrv ?? 0, 78.0, accuracy: 0.2)
        XCTAssertEqual(weekly.hrvDelta ?? 0, 14.0, accuracy: 0.2)

        // Manual scale & blood pressure logging auto-computes lean mass!
        store.logManualScaleReading(date: today, weightKg: 74.0, bodyFatPct: 15.0, leanMassKg: nil, systolicBp: 116, diastolicBp: 74)
        XCTAssertEqual(store.latestBodyWeightKg ?? 0, 74.0, accuracy: 0.1)
        XCTAssertEqual(store.latestBodyFatPct ?? 0, 15.0, accuracy: 0.1)
        XCTAssertEqual(store.latestLeanMassKg ?? 0, 62.9, accuracy: 0.2)
        XCTAssertEqual(store.latestBloodPressure?.sys, 116)
        XCTAssertEqual(store.latestBloodPressure?.dia, 74)

        // Home layout customization & health monitor toggle
        store.moveHomeSection(.nutrition, direction: -1)
        store.toggleHomeSection(.recentActivity)
        XCTAssertFalse(store.homeLayout.isSectionVisible(.recentActivity))
        store.toggleHealthMonitorMetric(.oxygenSaturation)
        XCTAssertFalse(store.homeLayout.isHealthMetricVisible(.oxygenSaturation))

        // Lab biomarker manual save
        store.addManualBiomarker(LabBiomarkerItem(
            id: "bio_vitd",
            name: "Vitamina D",
            value: 52.0,
            unit: "ng/mL",
            refMin: 30,
            refMax: 100,
            optimalMin: 40,
            optimalMax: 70,
            status: .optimal,
            category: "Vitaminas"
        ))
        XCTAssertTrue(store.latestBiomarkersByName.contains(where: { $0.name == "Vitamina D" }))

        // Share cards for Daily Overview, Biological Age, Weekly Review
        XCTAssertEqual(ShareCardPayload.build(for: .dailyOverview, store: store).metrics.count, 4)
        XCTAssertEqual(ShareCardPayload.build(for: .biologicalAge, store: store).metrics.count, 4)
        XCTAssertEqual(ShareCardPayload.build(for: .weeklyReview(weekly), store: store).metrics.count, 4)

        // Flush async persistence and verify reload
        store.flushPersistenceNow()
        let reloaded = ImprovingStore()
        XCTAssertFalse(reloaded.homeLayout.isSectionVisible(.recentActivity))
        XCTAssertTrue(reloaded.latestBiomarkersByName.contains(where: { $0.name == "Vitamina D" }))

        // Clean up test state so disk stays clean
        reloaded.resetHomeLayout()
        reloaded.labReports = []
        reloaded.realHistory = [:]
        reloaded.hasImportedOrPairedRealData = false
        reloaded.flushPersistenceNow()
    }
}
