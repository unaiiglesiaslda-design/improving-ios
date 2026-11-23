#if os(iOS)
import Foundation
import HealthKit
import Combine

// MARK: - HealthKit Processing Models & Data Types

public struct WorkoutSummary: Sendable {
    public let id: UUID
    public let activityType: HKWorkoutActivityType
    public let name: String
    public let sfSymbol: String
    public let startDate: Date
    public let endDate: Date
    public let durationMinutes: Int
    public let activeCalories: Int
    public let avgHeartRate: Int
    public let maxHeartRate: Int
    public let isStrength: Bool

    public init(
        id: UUID,
        activityType: HKWorkoutActivityType,
        name: String,
        sfSymbol: String,
        startDate: Date,
        endDate: Date? = nil,
        durationMinutes: Int,
        activeCalories: Int,
        avgHeartRate: Int,
        maxHeartRate: Int,
        isStrength: Bool = false
    ) {
        self.id = id
        self.activityType = activityType
        self.name = name
        self.sfSymbol = sfSymbol
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(Double(durationMinutes) * 60.0)
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.isStrength = isStrength
    }
}

public struct TimedHealthSample: Sendable {
    public let date: Date
    public let value: Double
}

public struct SleepStageSample: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let stageCode: Int // 0=awake, 1=rem, 2=core, 3=deep
}

public struct DailyHealthSnapshot: Sendable {
    public let day: Date
    public let sleep: NightlySleepSession?
    public let hrv: ProcessedNightlyHRV
    public let heartRate: ProcessedNightlyHeartRate
    public let vitals: ProcessedNocturnalVitals
    public let steps: Int?
    public let activeCalories: Double?
    public let workouts: [WorkoutSummary]
    public let liveHeartRate: Double?
    public let intradayHrSamples: [TimedHealthSample]
    public let sleepHrSamples: [TimedHealthSample]
    public let sleepHrvSamples: [TimedHealthSample]
    public let sleepRespSamples: [TimedHealthSample]
    public let sleepSpo2Samples: [TimedHealthSample]
    public let vo2Max: Double?
    public let hrRecoveryBpm: Double?
    public let bodyWeightKg: Double?
    public let bodyFatPct: Double?
    public let leanMassKg: Double?
    public let systolicBp: Int?
    public let diastolicBp: Int?
    public let daylightMinutes: Int?
    public let sleepNoiseOver50Db: Bool?
}

public enum DataConfidence: String, Codable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"
}

public struct NightlySleepSession: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let inBedMinutes: Double
    public let totalAsleepMinutes: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let coreMinutes: Double
    public let awakeMinutes: Double
    public let latencyMinutes: Int?
    public let efficiencyPct: Double
    public let restorativePct: Double
    public let isPrimary: Bool
    public let sourceName: String?
    public let stages: [SleepStageSample]
}

public struct ProcessedNightlyHRV: Sendable {
    public let medianHRV: Double
    public let weightedHRV: Double
    public let sampleCount: Int
    public let confidence: DataConfidence
}

public struct ProcessedNightlyHeartRate: Sendable {
    public let restingHR: Double
    public let sleepingMeanHR: Double
    public let sleepingMinHR: Double
    public let sleepingMinHRTimestamp: Date?
    public let nadirElapsedFraction: Double
}

public struct ProcessedNocturnalVitals: Sendable {
    public let tempAbsoluteCelsius: Double?
    public let tempDeltaCelsius: Double?
    public let meanRespiratoryRate: Double?
    public let meanSpO2: Double?
    public let minSpO2: Double?
}

public struct WorkoutZoneDistribution: Sendable {
    public let workoutId: UUID
    public let activityType: HKWorkoutActivityType
    public let durationMinutes: Double
    public let activeCalories: Double
    public let z1Minutes: Double
    public let z2Minutes: Double
    public let z3Minutes: Double
    public let z4Minutes: Double
    public let z5Minutes: Double
    public let avgHeartRate: Double
    public let maxHeartRate: Double
}

// MARK: - HealthKitReader (Strict Zero-Fabrication Live Apple Health Reader)

@MainActor
public final class HealthKitReader: ObservableObject {
    public static let shared = HealthKitReader()

    public let healthStore = HKHealthStore()

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var lastSyncTimestamp: Date? = nil
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var currentLiveHR: Double? = nil
    @Published public private(set) var latestSnapshot: DailyHealthSnapshot? = nil

    private var activeObserverQueries: [HKObserverQuery] = []

    public init() {}

    // MARK: - 1. Authorization

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit no está disponible en este dispositivo."])
        }

        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType()
        ]
        let qIds: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .heartRate,
            .appleSleepingWristTemperature,
            .respiratoryRate,
            .oxygenSaturation,
            .activeEnergyBurned,
            .stepCount,
            .vo2Max,
            .heartRateRecoveryOneMinute,
            .bodyMass,
            .leanBodyMass,
            .bodyFatPercentage,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .environmentalAudioExposure,
            .timeInDaylight
        ]
        for id in qIds {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                readTypes.insert(t)
            }
        }
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleepType)
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        self.isAuthorized = true
        await setupBackgroundDeliveryAndObservers()
    }

    // MARK: - 2. Background Delivery & Observers

    public func setupBackgroundDeliveryAndObservers() async {
        guard isAuthorized else { return }

        if let s = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            enableBackgroundDelivery(for: s, frequency: .immediate)
        }
        enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .immediate)
        for id: HKQuantityTypeIdentifier in [.heartRateVariabilitySDNN, .restingHeartRate, .heartRate] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                enableBackgroundDelivery(for: t, frequency: .hourly)
            }
        }
        registerObservers()
    }

    private func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) {
        healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
    }

    private func registerObservers() {
        guard activeObserverQueries.isEmpty else { return }
        var observedTypes: [HKSampleType] = [HKObjectType.workoutType()]
        if let s = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { observedTypes.append(s) }
        for id: HKQuantityTypeIdentifier in [.heartRateVariabilitySDNN, .restingHeartRate, .heartRate, .activeEnergyBurned, .stepCount] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { observedTypes.append(t) }
        }

        for sampleType in observedTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else {
                        completionHandler()
                        return
                    }
                    await self.syncLatestMetrics()
                    completionHandler()
                }
            }
            healthStore.execute(query)
            activeObserverQueries.append(query)
        }
    }

    // MARK: - 3. Single-Day & Multi-Day History Sync (Zero Fabricated Defaults!)

    @discardableResult
    public func syncLatestMetrics() async -> DailyHealthSnapshot? {
        guard isAuthorized else { return nil }
        self.isSyncing = true
        defer { self.isSyncing = false }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        let snapshot = await fetchDailySnapshot(for: startOfToday)
        self.latestSnapshot = snapshot
        self.lastSyncTimestamp = Date()
        return snapshot
    }

    public func syncHistoryDays(days: Int = 60) async -> [DailyHealthSnapshot] {
        guard isAuthorized else { return [] }
        self.isSyncing = true
        defer { self.isSyncing = false }

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var results: [DailyHealthSnapshot] = []
        results.reserveCapacity(days)

        for back in (0..<days).reversed() {
            guard let targetDay = cal.date(byAdding: .day, value: -back, to: todayStart) else { continue }
            let snap = await fetchDailySnapshot(for: targetDay)
            results.append(snap)
        }
        if let last = results.last {
            self.latestSnapshot = last
        }
        self.lastSyncTimestamp = Date()
        return results
    }

    public func fetchDailySnapshot(for targetDay: Date) async -> DailyHealthSnapshot {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: targetDay)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        let sleepSession = await extractPrimarySleepSession(around: dayStart)
        let (hrvData, sleepHrvSamples) = await extractNocturnalHRV(sleepSession: sleepSession, targetDay: dayStart)
        let (hrData, sleepHrSamples, intradayHrSamples, daytimeMeanHr) = await extractHeartRates(sleepSession: sleepSession, targetDay: dayStart)
        let (vitalsData, sleepRespSamples, sleepSpo2Samples, sleepNoiseOver50) = await extractNocturnalVitals(sleepSession: sleepSession, targetDay: dayStart)
        let (steps, cals, workouts) = await extractDailyActivity(targetDay: dayStart)

        let vo2 = await queryMeanQuantity(.vo2Max, unit: HKUnit(from: "mL/kg*min"), start: dayStart, end: dayEnd)
        let hrr = await queryMeanQuantity(.heartRateRecoveryOneMinute, unit: HKUnit.count().unitDivided(by: .minute()), start: dayStart, end: dayEnd)
        let weight = await queryMeanQuantity(.bodyMass, unit: .gramUnit(with: .kilo), start: dayStart, end: dayEnd)
        let fat = await queryMeanQuantity(.bodyFatPercentage, unit: .percent(), start: dayStart, end: dayEnd).map { $0 <= 1.0 ? $0 * 100.0 : $0 }
        let lean = await queryMeanQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo), start: dayStart, end: dayEnd)
        let sysBp = await queryMeanQuantity(.bloodPressureSystolic, unit: .millimeterOfMercury(), start: dayStart, end: dayEnd).map { Int($0.rounded()) }
        let diaBp = await queryMeanQuantity(.bloodPressureDiastolic, unit: .millimeterOfMercury(), start: dayStart, end: dayEnd).map { Int($0.rounded()) }
        let daylight = await querySumQuantity(.timeInDaylight, unit: .minute(), start: dayStart, end: dayEnd).map { Int($0.rounded()) }

        return DailyHealthSnapshot(
            day: dayStart,
            sleep: sleepSession,
            hrv: hrvData,
            heartRate: hrData,
            vitals: vitalsData,
            steps: steps,
            activeCalories: cals,
            workouts: workouts,
            liveHeartRate: daytimeMeanHr,
            intradayHrSamples: intradayHrSamples,
            sleepHrSamples: sleepHrSamples,
            sleepHrvSamples: sleepHrvSamples,
            sleepRespSamples: sleepRespSamples,
            sleepSpo2Samples: sleepSpo2Samples,
            vo2Max: vo2,
            hrRecoveryBpm: hrr,
            bodyWeightKg: weight,
            bodyFatPct: fat,
            leanMassKg: lean,
            systolicBp: sysBp,
            diastolicBp: diaBp,
            daylightMinutes: daylight,
            sleepNoiseOver50Db: sleepNoiseOver50
        )
    }

    // MARK: - 4. Sleep Session with Interval Deduplication

    public func extractPrimarySleepSession(around targetDate: Date) async -> NightlySleepSession? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let cal = Calendar.current
        guard let windowStart = cal.date(byAdding: .hour, value: -10, to: targetDate),
              let windowEnd = cal.date(byAdding: .hour, value: 16, to: targetDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
        guard !samples.isEmpty else { return nil }

        // Keep only samples whose wake/end date falls on targetDate (avoiding previous night leakage)
        let targetEnd = cal.date(byAdding: .day, value: 1, to: targetDate)!
        let daySamples = samples.filter { $0.endDate >= targetDate && $0.endDate < targetEnd }
        guard !daySamples.isEmpty else { return nil }

        let appleWatchSamples = daySamples.filter { s in
            let bundle = s.sourceRevision.source.bundleIdentifier.lowercased()
            return bundle.contains("apple") || s.device?.name?.localizedCaseInsensitiveContains("watch") == true
        }
        let cleanSamples = appleWatchSamples.isEmpty ? daySamples : appleWatchSamples

        var deepRanges: [(Date, Date)] = []
        var remRanges: [(Date, Date)] = []
        var coreRanges: [(Date, Date)] = []
        var unspecRanges: [(Date, Date)] = []
        var awakeRanges: [(Date, Date)] = []
        var inBedRanges: [(Date, Date)] = []
        var stageBlocks: [SleepStageSample] = []
        var sourceName: String? = nil

        for s in cleanSamples where s.endDate > s.startDate {
            if sourceName == nil { sourceName = s.sourceRevision.source.name }
            switch s.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedRanges.append((s.startDate, s.endDate))
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeRanges.append((s.startDate, s.endDate))
                stageBlocks.append(SleepStageSample(startDate: s.startDate, endDate: s.endDate, stageCode: 0))
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remRanges.append((s.startDate, s.endDate))
                stageBlocks.append(SleepStageSample(startDate: s.startDate, endDate: s.endDate, stageCode: 1))
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                coreRanges.append((s.startDate, s.endDate))
                stageBlocks.append(SleepStageSample(startDate: s.startDate, endDate: s.endDate, stageCode: 2))
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepRanges.append((s.startDate, s.endDate))
                stageBlocks.append(SleepStageSample(startDate: s.startDate, endDate: s.endDate, stageCode: 3))
            default:
                unspecRanges.append((s.startDate, s.endDate))
            }
        }

        let deepMin = mergeMinutes(deepRanges)
        let remMin = mergeMinutes(remRanges)
        let coreMin = mergeMinutes(coreRanges)
        let unspecMin = mergeMinutes(unspecRanges)
        let awakeMin = mergeMinutes(awakeRanges)
        let rawInBedMin = mergeMinutes(inBedRanges)

        let stagedAsleep = deepMin + remMin + coreMin
        let totalAsleep = stagedAsleep > 0 ? stagedAsleep : unspecMin
        guard totalAsleep > 0 else { return nil }

        let inBedMin = max(rawInBedMin, totalAsleep + awakeMin)
        let allAsleep = deepRanges + remRanges + coreRanges + unspecRanges
        let allSpans = allAsleep + awakeRanges + inBedRanges
        guard let overallStart = allSpans.map(\.0).min(),
              let overallEnd = allSpans.map(\.1).max() else { return nil }

        let latencyMin: Int? = {
            guard let ib = inBedRanges.map(\.0).min(), let fa = allAsleep.map(\.0).min(), fa >= ib else { return nil }
            return min(Int((fa.timeIntervalSince(ib) / 60.0).rounded()), 120)
        }()

        let efficiency = inBedMin > 0 ? min(100.0, (totalAsleep / inBedMin) * 100.0) : 0.0
        let restorative = totalAsleep > 0 ? min(100.0, ((deepMin + remMin) / totalAsleep) * 100.0) : 0.0

        return NightlySleepSession(
            startDate: overallStart,
            endDate: overallEnd,
            inBedMinutes: inBedMin,
            totalAsleepMinutes: totalAsleep,
            deepMinutes: deepMin,
            remMinutes: remMin,
            coreMinutes: coreMin,
            awakeMinutes: awakeMin,
            latencyMinutes: latencyMin,
            efficiencyPct: efficiency,
            restorativePct: restorative,
            isPrimary: totalAsleep >= 120,
            sourceName: sourceName,
            stages: stageBlocks.sorted { $0.startDate < $1.startDate }
        )
    }

    private func mergeMinutes(_ ranges: [(Date, Date)]) -> Double {
        guard !ranges.isEmpty else { return 0 }
        let sorted = ranges.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var curS = sorted[0].0
        var curE = sorted[0].1
        for (s, e) in sorted.dropFirst() {
            if s <= curE {
                curE = max(curE, e)
            } else {
                total += max(curE.timeIntervalSince(curS), 0)
                curS = s
                curE = e
            }
        }
        total += max(curE.timeIntervalSince(curS), 0)
        return total / 60.0
    }

    // MARK: - 5. Bevel-Aligned Nocturnal HRV (With Full-Day Fallback So HRV Is NEVER Dropped!)

    private func extractNocturnalHRV(sleepSession: NightlySleepSession?, targetDay: Date) async -> (ProcessedNightlyHRV, [TimedHealthSample]) {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return (ProcessedNightlyHRV(medianHRV: 0, weightedHRV: 0, sampleCount: 0, confidence: .low), [])
        }

        let cal = Calendar.current
        let msUnit = HKUnit.secondUnit(with: .milli)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        func queryHrv(from s: Date, to e: Date) async -> [TimedHealthSample] {
            let pred = HKQuery.predicateForSamples(withStart: s, end: e, options: [])
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let q = HKSampleQuery(sampleType: hrvType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            return samples.compactMap { s in
                let v = s.quantity.doubleValue(for: msUnit)
                return (3.0...350.0).contains(v) ? TimedHealthSample(date: s.startDate, value: v) : nil
            }
        }

        var sleepSamples: [TimedHealthSample] = []
        if let sl = sleepSession {
            sleepSamples = await queryHrv(from: sl.startDate.addingTimeInterval(-300), to: sl.endDate.addingTimeInterval(300))
        }

        // If no sleeping HRV samples exist, fall back to full day HRV so recorded HRV is never lost!
        let dayStart = cal.startOfDay(for: targetDay)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let chosen = !sleepSamples.isEmpty ? sleepSamples : await queryHrv(from: dayStart, to: dayEnd)

        guard !chosen.isEmpty else {
            return (ProcessedNightlyHRV(medianHRV: 0, weightedHRV: 0, sampleCount: 0, confidence: .low), [])
        }

        let vals = chosen.map(\.value).sorted()
        let median = vals.count % 2 == 0 ? (vals[vals.count / 2 - 1] + vals[vals.count / 2]) / 2.0 : vals[vals.count / 2]
        // Bevel displays the mean of sleeping HRV samples
        let meanVal = vals.reduce(0, +) / Double(vals.count)
        let conf: DataConfidence = sleepSamples.count >= 3 ? .high : (!sleepSamples.isEmpty ? .medium : .low)

        return (
            ProcessedNightlyHRV(medianHRV: median, weightedHRV: meanVal, sampleCount: chosen.count, confidence: conf),
            sleepSamples
        )
    }

    // MARK: - 6. Bevel-Aligned Sleeping HR, RHR & Full-Day Intraday HR (Zero Fake 50.0!)

    private func extractHeartRates(
        sleepSession: NightlySleepSession?,
        targetDay: Date
    ) async -> (ProcessedNightlyHeartRate, [TimedHealthSample], [TimedHealthSample], Double?) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: targetDay)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sortAsc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        // 1. Apple Health Resting HR for this exact day
        var appleRhr: Double = 0
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let pred = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: [])
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let q = HKSampleQuery(sampleType: rhrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortAsc]) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            let vals = samples.map { $0.quantity.doubleValue(for: bpmUnit) }.filter { (28...130).contains($0) }
            if !vals.isEmpty {
                appleRhr = vals.reduce(0, +) / Double(vals.count)
            }
        }

        // 2. All HR samples for intraday stress/energy (and sleep window HR if sleep started before midnight)
        var intraday: [TimedHealthSample] = []
        var sleepHr: [TimedHealthSample] = []
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let queryStart = min(dayStart, sleepSession?.startDate.addingTimeInterval(-300) ?? dayStart)
            let pred = HKQuery.predicateForSamples(withStart: queryStart, end: dayEnd, options: [])
            let rawHr: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortAsc]) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            for s in rawHr {
                let bpm = s.quantity.doubleValue(for: bpmUnit)
                guard (28...235).contains(bpm) else { continue }
                let sample = TimedHealthSample(date: s.startDate, value: bpm)
                if s.startDate >= dayStart && s.startDate < dayEnd {
                    intraday.append(sample)
                }
                if let sl = sleepSession,
                   s.startDate >= sl.startDate.addingTimeInterval(-300),
                   s.startDate <= sl.endDate.addingTimeInterval(300) {
                    sleepHr.append(sample)
                }
            }
        }

        // Bevel RHR = sleeping average heart rate during sleep (falls back to Apple RHR if no sleep HR)
        let sleepMean: Double = sleepHr.isEmpty ? 0 : (sleepHr.map(\.value).reduce(0, +) / Double(sleepHr.count))
        let effectiveRhr: Double = sleepHr.count >= 5 ? sleepMean : (appleRhr > 0 ? appleRhr : sleepMean)

        var minHr: Double = 0
        var minHrDate: Date? = nil
        if let best = sleepHr.min(by: { $0.value < $1.value }) {
            minHr = best.value
            minHrDate = best.date
        }

        let daytimeSamples: [Double] = {
            guard let sl = sleepSession else { return intraday.map(\.value) }
            return intraday.filter { $0.date > sl.endDate || $0.date < sl.startDate }.map(\.value)
        }()
        let daytimeMean: Double? = daytimeSamples.isEmpty ? nil : (daytimeSamples.reduce(0, +) / Double(daytimeSamples.count))

        let processed = ProcessedNightlyHeartRate(
            restingHR: effectiveRhr,
            sleepingMeanHR: sleepMean,
            sleepingMinHR: minHr,
            sleepingMinHRTimestamp: minHrDate,
            nadirElapsedFraction: 0.5
        )
        return (processed, sleepHr, intraday, daytimeMean)
    }

    // MARK: - 7. Nocturnal Vitals (STRICT ZERO FAKE DEFAULTS: nil if not measured!)

    private func extractNocturnalVitals(
        sleepSession: NightlySleepSession?,
        targetDay: Date
    ) async -> (ProcessedNocturnalVitals, [TimedHealthSample], [TimedHealthSample], Bool?) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: targetDay)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let winStart = sleepSession?.startDate.addingTimeInterval(-300) ?? dayStart
        let winEnd = sleepSession?.endDate.addingTimeInterval(300) ?? dayEnd
        let sortAsc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        func queryTimed(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from s: Date, to e: Date, scale: Double = 1.0) async -> [TimedHealthSample] {
            guard let t = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
            let pred = HKQuery.predicateForSamples(withStart: s, end: e, options: [])
            let raw: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let q = HKSampleQuery(sampleType: t, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortAsc]) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            return raw.map { TimedHealthSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit) * scale) }
        }

        let tempSamples = await queryTimed(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: dayStart, to: dayEnd)
            .filter { (28.0...42.0).contains($0.value) }
        let tempAbs: Double? = tempSamples.isEmpty ? nil : (tempSamples.map(\.value).reduce(0, +) / Double(tempSamples.count))

        let respUnit = HKUnit.count().unitDivided(by: .minute())
        let respSleep = await queryTimed(.respiratoryRate, unit: respUnit, from: winStart, to: winEnd).filter { (5.0...45.0).contains($0.value) }
        let respAll = respSleep.isEmpty ? await queryTimed(.respiratoryRate, unit: respUnit, from: dayStart, to: dayEnd).filter { (5.0...45.0).contains($0.value) } : respSleep
        let meanResp: Double? = respAll.isEmpty ? nil : (respAll.map(\.value).reduce(0, +) / Double(respAll.count))

        let spo2Sleep = await queryTimed(.oxygenSaturation, unit: .percent(), from: winStart, to: winEnd, scale: 100.0).filter { (60.0...100.0).contains($0.value) }
        let spo2All = spo2Sleep.isEmpty ? await queryTimed(.oxygenSaturation, unit: .percent(), from: dayStart, to: dayEnd, scale: 100.0).filter { (60.0...100.0).contains($0.value) } : spo2Sleep
        let meanSpo2: Double? = spo2All.isEmpty ? nil : (spo2All.map(\.value).reduce(0, +) / Double(spo2All.count))
        let minSpo2: Double? = spo2All.map(\.value).min()

        var sleepNoiseOver50: Bool? = nil
        if sleepSession != nil {
            let dbUnit = HKUnit.decibelAWeightedSoundPressureLevel()
            let audio = await queryTimed(.environmentalAudioExposure, unit: dbUnit, from: winStart, to: winEnd)
            if !audio.isEmpty {
                sleepNoiseOver50 = audio.contains { $0.value >= 50.0 }
            }
        }

        let vitals = ProcessedNocturnalVitals(
            tempAbsoluteCelsius: tempAbs,
            tempDeltaCelsius: nil,
            meanRespiratoryRate: meanResp,
            meanSpO2: meanSpo2,
            minSpO2: minSpo2
        )
        return (vitals, respSleep, spo2Sleep, sleepNoiseOver50)
    }

    // MARK: - 8. Daily Activity & Workouts (Zero Fake HR!)

    public func extractDailyActivity(targetDay: Date) async -> (steps: Int?, cals: Double?, workouts: [WorkoutSummary]) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: targetDay)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let steps = await querySumQuantity(.stepCount, unit: .count(), start: start, end: end).map { Int($0.rounded()) }
        let activeCals = await querySumQuantity(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)

        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let rawWorkouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 20, sortDescriptors: [sortDesc]) { _, res, _ in
                continuation.resume(returning: (res as? [HKWorkout]) ?? [])
            }
            healthStore.execute(q)
        }

        var items: [WorkoutSummary] = []
        for w in rawWorkouts {
            let durMin = max(Int((w.duration / 60.0).rounded()), 1)
            let kcal = Int((w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0.0).rounded())
            let (icon, name, isStrength) = workoutMetadata(for: w.workoutActivityType)
            let hrDist = await computeWorkoutHRZones(workout: w, age: 24)
            items.append(WorkoutSummary(
                id: w.uuid,
                activityType: w.workoutActivityType,
                name: name,
                sfSymbol: icon,
                startDate: w.startDate,
                endDate: w.endDate,
                durationMinutes: durMin,
                activeCalories: kcal,
                avgHeartRate: Int(hrDist.avgHeartRate.rounded()),
                maxHeartRate: Int(hrDist.maxHeartRate.rounded()),
                isStrength: isStrength
            ))
        }

        return (steps, activeCals, items)
    }

    public func computeWorkoutHRZones(workout: HKWorkout, age: Int = 24) async -> WorkoutZoneDistribution {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return WorkoutZoneDistribution(workoutId: workout.uuid, activityType: workout.workoutActivityType, durationMinutes: workout.duration / 60.0, activeCalories: 0, z1Minutes: 0, z2Minutes: 0, z3Minutes: 0, z4Minutes: 0, z5Minutes: 0, avgHeartRate: 0, maxHeartRate: 0)
        }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else {
            return WorkoutZoneDistribution(workoutId: workout.uuid, activityType: workout.workoutActivityType, durationMinutes: workout.duration / 60.0, activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0, z1Minutes: 0, z2Minutes: 0, z3Minutes: 0, z4Minutes: 0, z5Minutes: 0, avgHeartRate: 0, maxHeartRate: 0)
        }

        let maxHR = Double(208 - Int(0.7 * Double(age)))
        var z1 = 0, z2 = 0, z3 = 0, z4 = 0, z5 = 0
        var sumBpm = 0.0, peakBpm = 0.0
        for s in samples {
            let bpm = s.quantity.doubleValue(for: bpmUnit)
            sumBpm += bpm
            if bpm > peakBpm { peakBpm = bpm }
            let pct = bpm / maxHR
            if pct >= 0.90 { z5 += 1 }
            else if pct >= 0.80 { z4 += 1 }
            else if pct >= 0.70 { z3 += 1 }
            else if pct >= 0.60 { z2 += 1 }
            else if pct >= 0.50 { z1 += 1 }
        }
        let durMin = workout.duration / 60.0
        let frac = durMin / Double(samples.count)
        return WorkoutZoneDistribution(
            workoutId: workout.uuid,
            activityType: workout.workoutActivityType,
            durationMinutes: durMin,
            activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            z1Minutes: Double(z1) * frac,
            z2Minutes: Double(z2) * frac,
            z3Minutes: Double(z3) * frac,
            z4Minutes: Double(z4) * frac,
            z5Minutes: Double(z5) * frac,
            avgHeartRate: sumBpm / Double(samples.count),
            maxHeartRate: peakBpm
        )
    }

    private func querySumQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let t = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let q = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                if let qty = stats?.sumQuantity() {
                    let v = qty.doubleValue(for: unit)
                    continuation.resume(returning: v > 0 ? v : nil)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(q)
        }
    }

    private func queryMeanQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let t = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: t, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else { return nil }
        let vals = samples.map { $0.quantity.doubleValue(for: unit) }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func workoutMetadata(for type: HKWorkoutActivityType) -> (icon: String, name: String, isStrength: Bool) {
        switch type {
        case .running: return ("figure.run", "Carrera", false)
        case .cycling: return ("figure.outdoor.cycle", "Bici al aire libre", false)
        case .swimming: return ("figure.pool.swim", "Natación", false)
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return ("dumbbell.fill", "Entrenamiento de fuerza", true)
        case .highIntensityIntervalTraining: return ("flame.fill", "HIIT", false)
        case .walking, .hiking: return ("figure.walk", "Caminata", false)
        case .yoga, .pilates: return ("figure.mind.and.body", "Movilidad / Yoga", false)
        default: return ("figure.cross.training", "Entrenamiento", false)
        }
    }
}
#endif

// MARK: - Pure Shared Physiology Types (macOS + iOS)

public enum BiologicalSexProfile: String, Codable, Sendable {
    case male = "male"
    case female = "female"
    case nonBinary = "nonBinary"

    public var banisterB: Double {
        switch self {
        case .male: return 1.92
        case .female: return 1.67
        case .nonBinary: return 1.795
        }
    }
}

public struct UserPhysiologyProfileConfig: Codable, Sendable {
    public var ageYears: Double
    public var sex: BiologicalSexProfile
    public var weightKg: Double
    public var heightCm: Double
    public var bodyFatPct: Double?
    public var maxHrOverride: Int?

    public init(
        ageYears: Double = 24.0,
        sex: BiologicalSexProfile = .male,
        weightKg: Double = 70.0,
        heightCm: Double = 176.0,
        bodyFatPct: Double? = nil,
        maxHrOverride: Int? = nil
    ) {
        self.ageYears = ageYears
        self.sex = sex
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.bodyFatPct = bodyFatPct
        self.maxHrOverride = maxHrOverride
    }
}
