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
    }
}
