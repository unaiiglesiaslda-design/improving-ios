import XCTest
@testable import Improving

final class AppleHealthExportImporterTests: XCTestCase {

    private let sampleXml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE HealthData [
    <!ELEMENT HealthData (Record*,Workout*)>
    ]>
    <HealthData locale="es_ES">
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

    func testParsesAppleHealthXmlAndExtracts5MinStressAndSleepDetail() throws {
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

        // Verify 5-minute intraday stress & energy points extracted from real HR timestamps
        XCTAssertGreaterThanOrEqual(day.stressSamples5m.count, 5)
        XCTAssertGreaterThanOrEqual(day.energySamples5m.count, 5)

        // Verify SleepSessionDetail extracted cleanly
        let sess = try XCTUnwrap(day.sleepSession)
        XCTAssertEqual(sess.sourceName, "Apple Watch de Unai")
        XCTAssertEqual(sess.latencyMinutes, 10)
        XCTAssertFalse(sess.stages.isEmpty)
        XCTAssertFalse(sess.sleepHrSamples.isEmpty)
        XCTAssertFalse(sess.sleepHrvSamples.isEmpty)
        XCTAssertFalse(sess.sleepRespSamples.isEmpty)
        XCTAssertFalse(sess.sleepSpo2Samples.isEmpty)
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
        // Missing sensors MUST stay nil (never fabricated!)
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

        let range = WhoopPhysiologyEngine.optimalTargetRange(for: rec)
        XCTAssertLessThan(range.lowerBound, range.upperBound)
    }
}
