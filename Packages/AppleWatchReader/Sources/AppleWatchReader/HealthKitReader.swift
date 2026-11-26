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
    public let basalCalories: Double?
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
    public let asleepIntervals: [(Date, Date)]
    public let awakeIntervals: [(Date, Date)]

    public init(
        startDate: Date,
        endDate: Date,
        inBedMinutes: Double,
        totalAsleepMinutes: Double,
        deepMinutes: Double,
        remMinutes: Double,
        coreMinutes: Double,
        awakeMinutes: Double,
        latencyMinutes: Int?,
        efficiencyPct: Double,
        restorativePct: Double,
        isPrimary: Bool,
        sourceName: String?,
        stages: [SleepStageSample],
        asleepIntervals: [(Date, Date)] = [],
        awakeIntervals: [(Date, Date)] = []
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.inBedMinutes = inBedMinutes
        self.totalAsleepMinutes = totalAsleepMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.latencyMinutes = latencyMinutes
        self.efficiencyPct = efficiencyPct
        self.restorativePct = restorativePct
        self.isPrimary = isPrimary
        self.sourceName = sourceName
        self.stages = stages
        self.asleepIntervals = asleepIntervals
        self.awakeIntervals = awakeIntervals
    }

    /// Bevel "Entire Sleep" predicate: returns true ONLY when timestamp falls inside an actual ASLEEP interval
    /// (Core / Deep / REM / Asleep), explicitly excluding `InBed` before falling asleep and `Awake` interruptions!
    public func isDuringAsleep(_ date: Date, toleranceSec: TimeInterval) -> Bool {
        for (awS, awE) in awakeIntervals where awE.timeIntervalSince(awS) >= 120 {
            if date > awS.addingTimeInterval(30) && date < awE.addingTimeInterval(-30) {
                return false
            }
        }
        if !asleepIntervals.isEmpty {
            return asleepIntervals.contains { (s, e) in
                date >= s.addingTimeInterval(-toleranceSec) && date <= e.addingTimeInterval(toleranceSec)
            }
        }
        return date >= startDate.addingTimeInterval(-toleranceSec) && date <= endDate.addingTimeInterval(toleranceSec)
    }
}

public struct ProcessedNightlyHRV: Sendable {
    public let medianHRV: Double
    public let weightedHRV: Double
    public let sampleCount: Int
    public let confidence: DataConfidence
    public let method: String

    public init(
        medianHRV: Double,
        weightedHRV: Double,
        sampleCount: Int,
        confidence: DataConfidence,
        method: String = "RMSSD · Todo el sueño"
    ) {
        self.medianHRV = medianHRV
        self.weightedHRV = weightedHRV
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.method = method
    }
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

    /// Real user physiological parameters configured from `ImprovingStore.userProfile`
    /// so HR-zone computation uses the user's true age & resting HR instead of a hardcoded default.
    public var configuredAgeYears: Int = 24
    public var configuredRestingHrBpm: Double = 55.0

    private var activeObserverQueries: [HKObserverQuery] = []

    public init() {}

    // MARK: - 1. Authorization

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit no está disponible en este dispositivo."])
        }

        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.heartbeat()
        ]
        let qIds: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .heartRate,
            .appleSleepingWristTemperature,
            .respiratoryRate,
            .oxygenSaturation,
            .activeEnergyBurned,
            .basalEnergyBurned,
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

    /// Re-registers HealthKit observer queries & background delivery on cold launch when the user
    /// previously granted HealthKit access (never prompts a UI sheet).
    public func restoreBackgroundObserversIfAuthorized() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
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
        let basalCals = await querySumQuantity(.basalEnergyBurned, unit: .kilocalorie(), start: dayStart, end: dayEnd)

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
            basalCalories: basalCals,
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

        // Keep sleep belonging to this night:
        // - Include pre-midnight evening blocks (>= 18:00 prev day)
        // - Exclude next-night bedtime blocks starting >= 19:30 on targetDate so daytime HRV never leaks in!
        guard let prevEveningCutoff = cal.date(byAdding: .hour, value: -6, to: targetDate),
              let nextNightCutoff = cal.date(byAdding: .minute, value: 19 * 60 + 30, to: targetDate) else { return nil }
        let daySamples = samples.filter { $0.endDate >= prevEveningCutoff && $0.startDate < nextNightCutoff }
        guard !daySamples.isEmpty else { return nil }

        let appleWatchSamples = daySamples.filter { s in
            let bundle = s.sourceRevision.source.bundleIdentifier.lowercased()
            return bundle.contains("apple") || s.device?.name?.localizedCaseInsensitiveContains("watch") == true
        }
        let sourceFiltered = appleWatchSamples.isEmpty ? daySamples : appleWatchSamples

        // Cluster contiguous sleep blocks (gap <= 90 min) and pick the primary longest overnight session (ignores naps!)
        let sortedByStart = sourceFiltered.sorted { $0.startDate < $1.startDate }
        var clusters: [[HKCategorySample]] = []
        var currentCluster: [HKCategorySample] = []
        var currentEnd: Date = .distantPast
        for s in sortedByStart where s.endDate > s.startDate {
            if currentCluster.isEmpty {
                currentCluster = [s]
                currentEnd = s.endDate
            } else if s.startDate.timeIntervalSince(currentEnd) <= 90 * 60 {
                currentCluster.append(s)
                if s.endDate > currentEnd { currentEnd = s.endDate }
            } else {
                clusters.append(currentCluster)
                currentCluster = [s]
                currentEnd = s.endDate
            }
        }
        if !currentCluster.isEmpty { clusters.append(currentCluster) }

        let cleanSamples: [HKCategorySample] = clusters.max { a, b in
            let asleepA = mergeMinutes(a.filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue && $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }.map { ($0.startDate, $0.endDate) })
            let asleepB = mergeMinutes(b.filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue && $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }.map { ($0.startDate, $0.endDate) })
            return asleepA < asleepB
        } ?? sourceFiltered

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

        // Strict staged-sleep priority: when Watch staged sleep exists, drop overlapping iPhone `unspecRanges`!
        let allAsleep = stagedAsleep > 0 ? (deepRanges + remRanges + coreRanges) : unspecRanges
        guard let asleepStart = allAsleep.map(\.0).min(),
              let asleepEnd = allAsleep.map(\.1).max() else { return nil }
        // Only keep InBed spans within 60m before falling asleep / 30m after waking (drops awake bedtime schedules)
        let nearInBed = inBedRanges.filter { $0.1 >= asleepStart.addingTimeInterval(-3600) && $0.0 <= asleepEnd.addingTimeInterval(1800) }
        let nearInBedMin = mergeMinutes(nearInBed)
        let inBedMin = max(nearInBedMin, totalAsleep + awakeMin)
        let overallStart = min(asleepStart, nearInBed.map(\.0).min() ?? asleepStart)
        let overallEnd = max(asleepEnd, awakeRanges.map(\.1).max() ?? asleepEnd)

        let latencyMin: Int? = {
            guard let ib = nearInBed.map(\.0).min(), asleepStart >= ib else { return nil }
            return min(Int((asleepStart.timeIntervalSince(ib) / 60.0).rounded()), 120)
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
            stages: stageBlocks.sorted { $0.startDate < $1.startDate },
            asleepIntervals: allAsleep,
            awakeIntervals: awakeRanges
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

    // MARK: - 5. Bevel / WHOOP Beat-to-Beat RMSSD HRV Over Entire Sleep ("Todo el sueño")

    private func extractHeartbeatSeriesRmssd(from s: Date, to e: Date) async -> [TimedHealthSample] {
        let hbType = HKSeriesType.heartbeat()
        let pred = HKQuery.predicateForSamples(withStart: s, end: e, options: [])
        let sortAsc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let seriesSamples: [HKHeartbeatSeriesSample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: hbType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortAsc]) { _, res, _ in
                continuation.resume(returning: (res as? [HKHeartbeatSeriesSample]) ?? [])
            }
            healthStore.execute(q)
        }
        guard !seriesSamples.isEmpty else { return [] }

        var results: [TimedHealthSample] = []
        results.reserveCapacity(seriesSamples.count)

        for sample in seriesSamples {
            let beats: [(TimeInterval, Bool)] = await withCheckedContinuation { continuation in
                var collected: [(TimeInterval, Bool)] = []
                var resumed = false
                let q = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, timeSinceStart, precededByGap, done, error in
                    if error == nil && !(done && collected.isEmpty && timeSinceStart == 0) {
                        collected.append((timeSinceStart, precededByGap))
                    }
                    if (done || error != nil) && !resumed {
                        resumed = true
                        continuation.resume(returning: collected)
                    }
                }
                healthStore.execute(q)
            }
            if let rmssd = computeBeatSeriesRmssd(beats: beats) {
                results.append(TimedHealthSample(date: sample.endDate, value: rmssd))
            }
        }
        return results
    }

    /// Computes true Bevel/WHOOP RMSSD (ms) from raw `HKHeartbeatSeriesQuery` beats,
    /// splitting across sensor gaps (`precededByGap`) and rejecting ectopic/motion artifacts.
    private func computeBeatSeriesRmssd(beats: [(TimeInterval, Bool)]) -> Double? {
        guard beats.count >= 6 else { return nil }
        var segments: [[Double]] = []
        var cur: [Double] = []
        var prevTime: TimeInterval? = nil

        for (t, gap) in beats {
            if gap {
                if !cur.isEmpty { segments.append(cur); cur = [] }
                prevTime = t
                continue
            }
            if let p = prevTime {
                let rrMs = (t - p) * 1000.0
                if (300.0...2000.0).contains(rrMs) {
                    cur.append(rrMs)
                } else if !cur.isEmpty {
                    segments.append(cur)
                    cur = []
                }
            }
            prevTime = t
        }
        if !cur.isEmpty { segments.append(cur) }

        let allValid = segments.flatMap { $0 }
        guard allValid.count >= 5 else { return nil }
        let sorted = allValid.sorted()
        let medRR = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        let maxDev = medRR * 0.25
        let maxJump = min(300.0, medRR * 0.30)

        var sqSum = 0.0
        var count = 0
        for seg in segments {
            var prevClean: Double? = nil
            for rr in seg {
                guard abs(rr - medRR) <= maxDev else { prevClean = nil; continue }
                if let p = prevClean {
                    let d = abs(rr - p)
                    if d <= maxJump {
                        sqSum += d * d
                        count += 1
                    }
                }
                prevClean = rr
            }
        }
        guard count >= 4 else { return nil }
        let rmssd = sqrt(sqSum / Double(count))
        return (3.0...350.0).contains(rmssd) ? rmssd : nil
    }

    private func aggregateCleanedHrv(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        if values.count < 4 { return values.reduce(0, +) / Double(values.count) }
        let sorted = values.sorted()
        let med = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        let absDevs = sorted.map { abs($0 - med) }.sorted()
        let mad = absDevs.count % 2 == 1 ? absDevs[absDevs.count / 2] : (absDevs[absDevs.count / 2 - 1] + absDevs[absDevs.count / 2]) / 2.0
        let sigma = max(1.4826 * mad, med * 0.18, 12.0)
        let cleaned = values.filter { abs($0 - med) <= 3.0 * sigma }
        let pool = cleaned.isEmpty ? values : cleaned
        return pool.reduce(0, +) / Double(pool.count)
    }

    private func extractNocturnalHRV(sleepSession: NightlySleepSession?, targetDay: Date) async -> (ProcessedNightlyHRV, [TimedHealthSample]) {
        let cal = Calendar.current
        let msUnit = HKUnit.secondUnit(with: .milli)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        func querySdnn(from s: Date, to e: Date) async -> [TimedHealthSample] {
            guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
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

        // Priority 1 & 2: STRICTLY Entire Sleep ("Todo el sueño") — Beat-to-Beat RMSSD first, SDNN fallback
        var sleepSamples: [TimedHealthSample] = []
        var methodLabel = "RMSSD · Todo el sueño"

        if let sl = sleepSession {
            let winStart = sl.startDate.addingTimeInterval(-120)
            let winEnd = sl.endDate.addingTimeInterval(120)
            let rmssdSleep = (await extractHeartbeatSeriesRmssd(from: winStart, to: winEnd))
                .filter { sl.isDuringAsleep($0.date, toleranceSec: 90) }
            if !rmssdSleep.isEmpty {
                sleepSamples = rmssdSleep
                methodLabel = "RMSSD · Todo el sueño"
            } else {
                let sdnnSleep = (await querySdnn(from: winStart, to: winEnd))
                    .filter { sl.isDuringAsleep($0.date, toleranceSec: 90) }
                if !sdnnSleep.isEmpty {
                    sleepSamples = sdnnSleep
                    methodLabel = "SDNN · Todo el sueño"
                }
            }
        }

        // Priority 3: If no sleep session recorded, check overnight window (22:00 prev day – 11:00) before full-day!
        var chosen = sleepSamples
        if chosen.isEmpty {
            let dayStart = cal.startOfDay(for: targetDay)
            let noctStart = cal.date(byAdding: .hour, value: -2, to: dayStart) ?? dayStart
            let noctEnd = cal.date(byAdding: .hour, value: 11, to: dayStart) ?? dayStart
            let noctRmssd = await extractHeartbeatSeriesRmssd(from: noctStart, to: noctEnd)
            if !noctRmssd.isEmpty {
                chosen = noctRmssd
                methodLabel = "RMSSD · Nocturna"
            } else {
                let noctSdnn = await querySdnn(from: noctStart, to: noctEnd)
                if !noctSdnn.isEmpty {
                    chosen = noctSdnn
                    methodLabel = "SDNN · Nocturna"
                } else {
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
                    let dayRmssd = await extractHeartbeatSeriesRmssd(from: dayStart, to: dayEnd)
                    if !dayRmssd.isEmpty {
                        chosen = dayRmssd
                        methodLabel = "RMSSD · Día"
                    } else {
                        chosen = await querySdnn(from: dayStart, to: dayEnd)
                        methodLabel = "SDNN · Día"
                    }
                }
            }
        }

        guard !chosen.isEmpty else {
            return (ProcessedNightlyHRV(medianHRV: 0, weightedHRV: 0, sampleCount: 0, confidence: .low, method: methodLabel), [])
        }

        let vals = chosen.map(\.value).sorted()
        let median = vals.count % 2 == 0 ? (vals[vals.count / 2 - 1] + vals[vals.count / 2]) / 2.0 : vals[vals.count / 2]
        let cleanedMean = aggregateCleanedHrv(vals)
        let conf: DataConfidence = sleepSamples.count >= 3 ? .high : (!sleepSamples.isEmpty ? .medium : .low)

        return (
            ProcessedNightlyHRV(medianHRV: median, weightedHRV: cleanedMean, sampleCount: chosen.count, confidence: conf, method: methodLabel),
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
                if let sl = sleepSession, sl.isDuringAsleep(s.startDate, toleranceSec: 30) {
                    sleepHr.append(sample)
                }
            }
        }

        // Bevel RHR = sleeping average heart rate strictly during ASLEEP stages (excludes InBed & Awake!)
        let sleepMean: Double = sleepHr.isEmpty ? 0 : (sleepHr.map(\.value).reduce(0, +) / Double(sleepHr.count))
        let effectiveRhr: Double = sleepHr.count >= 3 ? sleepMean : (appleRhr > 0 ? appleRhr : sleepMean)

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

        // Sleeping wrist temperature often starts before midnight at bedtime and ends on wake-up morning
        let tempWinStart = min(dayStart, sleepSession?.startDate.addingTimeInterval(-3600) ?? dayStart)
        let tempSamples = await queryTimed(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: tempWinStart, to: dayEnd)
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
            let hrDist = await computeWorkoutHRZones(workout: w, age: configuredAgeYears, restingHr: configuredRestingHrBpm)
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

    public func computeWorkoutHRZones(workout: HKWorkout, age: Int? = nil, restingHr: Double? = nil) async -> WorkoutZoneDistribution {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return WorkoutZoneDistribution(workoutId: workout.uuid, activityType: workout.workoutActivityType, durationMinutes: workout.duration / 60.0, activeCalories: 0, z1Minutes: 0, z2Minutes: 0, z3Minutes: 0, z4Minutes: 0, z5Minutes: 0, avgHeartRate: 0, maxHeartRate: 0)
        }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sortAsc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortAsc]) { _, res, _ in
                continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else {
            return WorkoutZoneDistribution(workoutId: workout.uuid, activityType: workout.workoutActivityType, durationMinutes: workout.duration / 60.0, activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0, z1Minutes: 0, z2Minutes: 0, z3Minutes: 0, z4Minutes: 0, z5Minutes: 0, avgHeartRate: 0, maxHeartRate: 0)
        }

        let effAge = Double(min(max(age ?? configuredAgeYears, 13), 95))
        let maxHR = max(125.0, 208.0 - 0.7 * effAge)
        let rhr = min(max(restingHr ?? configuredRestingHrBpm, 38.0), 95.0)
        let hrr = max(maxHR - rhr, 40.0)

        // True dt-weighted Karvonen HRR zone integration (handles irregular Apple Watch sampling cadence!)
        var z1Min = 0.0, z2Min = 0.0, z3Min = 0.0, z4Min = 0.0, z5Min = 0.0
        var weightedBpmSum = 0.0, totalDtMin = 0.0, peakBpm = 0.0
        for idx in 0..<samples.count {
            let s = samples[idx]
            let bpm = s.quantity.doubleValue(for: bpmUnit)
            if bpm > peakBpm { peakBpm = bpm }
            let nextTime: Date = (idx + 1 < samples.count) ? samples[idx + 1].startDate : workout.endDate
            let dtMin = min(max(nextTime.timeIntervalSince(s.startDate) / 60.0, 0.05), 2.5)
            weightedBpmSum += bpm * dtMin
            totalDtMin += dtMin

            let hrrFrac = (bpm - rhr) / hrr
            if hrrFrac >= 0.90 { z5Min += dtMin }
            else if hrrFrac >= 0.80 { z4Min += dtMin }
            else if hrrFrac >= 0.70 { z3Min += dtMin }
            else if hrrFrac >= 0.60 { z2Min += dtMin }
            else if hrrFrac >= 0.50 { z1Min += dtMin }
        }
        let durMin = workout.duration / 60.0
        let avgBpm = totalDtMin > 0 ? (weightedBpmSum / totalDtMin) : samples.map { $0.quantity.doubleValue(for: bpmUnit) }.reduce(0, +) / Double(samples.count)
        return WorkoutZoneDistribution(
            workoutId: workout.uuid,
            activityType: workout.workoutActivityType,
            durationMinutes: durMin,
            activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            z1Minutes: z1Min,
            z2Minutes: z2Min,
            z3Minutes: z3Min,
            z4Minutes: z4Min,
            z5Minutes: z5Min,
            avgHeartRate: avgBpm,
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
