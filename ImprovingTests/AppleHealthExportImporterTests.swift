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
        XCTAssertEqual(trends.map(\.label), ["3 días", "7 días", "14 días", "30 días", "90 días"])
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

    func testGeminiApiKeySanitizationAndSupportedModels() {
        XCTAssertEqual(GeminiCoachService.sanitizeApiKey("  \"Bearer AIzaSyTestKey123 \" \n"), "AIzaSyTestKey123")
        XCTAssertEqual(GeminiCoachService.sanitizeApiKey("'AIzaSyClean456'"), "AIzaSyClean456")
        XCTAssertEqual(GeminiCoachService.supportedModels.first, "gemini-2.5-flash")
        XCTAssertTrue(GeminiCoachService.supportedModels.contains("gemini-2.5-flash-lite"))
    }
}
