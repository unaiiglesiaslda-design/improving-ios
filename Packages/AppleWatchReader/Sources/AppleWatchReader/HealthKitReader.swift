#if os(iOS)
import Foundation
import HealthKit
import Combine

// MARK: - HealthKit Processing Models & Data Types

/// One workout read from HealthKit (Apple Watch or any other source).
public struct WorkoutSummary: Sendable {
    public let id: UUID
    public let activityType: HKWorkoutActivityType
    public let name: String
    public let sfSymbol: String
    public let startDate: Date
    public let durationMinutes: Int
    public let activeCalories: Int
    public let avgHeartRate: Int
    public let maxHeartRate: Int
}

/// Everything the reader extracts for one day. Pure data: no scoring, no persistence.
public struct DailyHealthSnapshot: Sendable {
    public let day: Date
    public let sleep: NightlySleepSession?
    public let hrv: ProcessedNightlyHRV
    public let heartRate: ProcessedNightlyHeartRate
    public let vitals: ProcessedNocturnalVitals
    public let steps: Int
    public let activeCalories: Double
    public let workouts: [WorkoutSummary]
    public let liveHeartRate: Double?
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
    public let awakeMinutes: Double // WASO
    public let efficiencyPct: Double // (totalAsleep / inBed) * 100
    public let restorativePct: Double // ((deep + rem) / totalAsleep) * 100
    public let isPrimary: Bool
}

public struct ProcessedNightlyHRV: Sendable {
    public let medianHRV: Double
    public let weightedHRV: Double // 60% weight to last third of night
    public let sampleCount: Int
    public let confidence: DataConfidence
}

public struct ProcessedNightlyHeartRate: Sendable {
    public let restingHR: Double
    public let sleepingMinHR: Double
    public let sleepingMinHRTimestamp: Date?
    public let nadirElapsedFraction: Double // 0.0 (early) to 1.0 (late in the night)
}

public struct ProcessedNocturnalVitals: Sendable {
    public let tempDeltaCelsius: Double
    public let meanRespiratoryRate: Double
    public let meanSpO2: Double
    public let minSpO2: Double
}

public struct WorkoutZoneDistribution: Sendable {
    public let workoutId: UUID
    public let activityType: HKWorkoutActivityType
    public let durationMinutes: Double
    public let activeCalories: Double
    public let z1Minutes: Double // 50-60% FC_Max
    public let z2Minutes: Double // 60-70% FC_Max
    public let z3Minutes: Double // 70-80% FC_Max
    public let z4Minutes: Double // 80-90% FC_Max
    public let z5Minutes: Double // 90-100% FC_Max
    public let avgHeartRate: Double
    public let maxHeartRate: Double
}

// MARK: - HealthKitReader (read-only access to Apple Watch / Apple Health data)

@MainActor
public final class HealthKitReader: ObservableObject {
    public static let shared = HealthKitReader()

    public let healthStore = HKHealthStore()

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var lastSyncTimestamp: Date? = nil
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var currentLiveHR: Double? = nil
    /// Latest snapshot produced by `syncLatestMetrics()`; observers re-publish it automatically.
    @Published public private(set) var latestSnapshot: DailyHealthSnapshot? = nil

    // Observers retention
    private var activeObserverQueries: [HKObserverQuery] = []

    public init() {}

    // MARK: - 1. Authorization & Types Setup
    
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit no estÃ¡ disponible en este dispositivo."])
        }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!,
            HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!,
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .leanBodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.workoutType()
        ]

        // Read-only: this package never writes to Apple Health.
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        self.isAuthorized = true
        
        // Setup background deliveries and observers
        await setupBackgroundDeliveryAndObservers()
    }

    // MARK: - 2. Background Delivery & Observers

    public func setupBackgroundDeliveryAndObservers() async {
        guard isAuthorized else { return }

        // Frecuencia .immediate para SueÃ±o y Entrenamientos
        enableBackgroundDelivery(for: HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!, frequency: .immediate)
        enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .immediate)

        // Frecuencia .hourly para VFC, RHR y FC continua
        enableBackgroundDelivery(for: HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, frequency: .hourly)
        enableBackgroundDelivery(for: HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!, frequency: .hourly)
        enableBackgroundDelivery(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!, frequency: .hourly)

        registerObservers()
    }

    private func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) {
        healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
            if let error = error {
                print("[HealthKitManager] Error habilitando background delivery para \(type): \(error.localizedDescription)")
            }
        }
    }

    private func registerObservers() {
        let observedTypes: [HKSampleType] = [
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!
        ]

        for sampleType in observedTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self = self else {
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

    // MARK: - 3. Core Sync & Historical Ingestion (60 Days Cold Start)

    @discardableResult
    public func syncLatestMetrics() async -> DailyHealthSnapshot? {
        guard isAuthorized else { return nil }
        self.isSyncing = true
        defer { self.isSyncing = false }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // 1. Process Nightly Sleep Session
        let sleepSession = await extractPrimarySleepSession(around: startOfToday)
        
        // 2. Process Nocturnal HRV (filtered strictly to sleep window)
        let hrvData = await extractNocturnalHRV(sleepSession: sleepSession, targetDay: startOfToday)
        
        // 3. Process RHR and Sleeping Min HR (nadir)
        let hrData = await extractNocturnalHeartRates(sleepSession: sleepSession, targetDay: startOfToday)
        
        // 4. Process Secondary Nocturnal Vitals
        let vitalsData = await extractNocturnalVitals(sleepSession: sleepSession)
        
        // 5. Activity, Steps and Workouts
        let (steps, cals, workouts) = await extractDailyActivity(targetDay: startOfToday)

        // 6. Publish the snapshot (consumers decide what to do with it)
        let snapshot = DailyHealthSnapshot(
            day: startOfToday,
            sleep: sleepSession,
            hrv: hrvData,
            heartRate: hrData,
            vitals: vitalsData,
            steps: steps,
            activeCalories: cals,
            workouts: workouts,
            liveHeartRate: currentLiveHR
        )
        self.latestSnapshot = snapshot
        self.lastSyncTimestamp = Date()
        return snapshot
    }

    // MARK: - 4. Advanced Sleep Analysis & Overlap Deduplication

    public func extractPrimarySleepSession(around targetDate: Date) async -> NightlySleepSession? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let calendar = Calendar.current
        // Window from 18:00 of previous day to 14:00 of target day
        guard let windowStart = calendar.date(byAdding: .hour, value: -14, to: targetDate),
              let windowEnd = calendar.date(byAdding: .hour, value: 14, to: targetDate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        // Filter and prioritize native Apple Watch samples over third-party apps
        let appleWatchSamples = samples.filter { sample in
            let bundle = sample.sourceRevision.source.bundleIdentifier.lowercased()
            return bundle.contains("apple") || sample.device?.name?.contains("Apple Watch") == true
        }
        let cleanSamples = appleWatchSamples.isEmpty ? samples : appleWatchSamples

        // Merge intervals separated by less than 20 minutes of awake
        var mergedIntervals: [(start: Date, end: Date, value: Int)] = []
        for sample in cleanSamples {
            if let last = mergedIntervals.last,
               sample.startDate.timeIntervalSince(last.end) < 20 * 60,
               last.value != HKCategoryValueSleepAnalysis.awake.rawValue,
               sample.value != HKCategoryValueSleepAnalysis.awake.rawValue {
                // Merge contiguous sleep stages
                mergedIntervals[mergedIntervals.count - 1].end = max(last.end, sample.endDate)
            } else {
                mergedIntervals.append((start: sample.startDate, end: sample.endDate, value: sample.value))
            }
        }

        // Tally minutes by sleep stage
        var inBedMin: Double = 0
        var deepMin: Double = 0
        var remMin: Double = 0
        var coreMin: Double = 0
        var awakeMin: Double = 0
        var overallStart: Date?
        var overallEnd: Date?

        for sample in cleanSamples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            if duration <= 0 { continue }

            if overallStart == nil || sample.startDate < overallStart! { overallStart = sample.startDate }
            if overallEnd == nil || sample.endDate > overallEnd! { overallEnd = sample.endDate }

            switch sample.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedMin += duration
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeMin += duration
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepMin += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remMin += duration
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                coreMin += duration
            default:
                // Unspecified asleep
                coreMin += duration
            }
        }

        let totalAsleep = deepMin + remMin + coreMin
        if inBedMin < totalAsleep { inBedMin = totalAsleep + awakeMin }
        let efficiency = inBedMin > 0 ? min(100.0, (totalAsleep / inBedMin) * 100.0) : 0.0
        let restorative = totalAsleep > 0 ? min(100.0, ((deepMin + remMin) / totalAsleep) * 100.0) : 0.0

        return NightlySleepSession(
            startDate: overallStart ?? windowStart,
            endDate: overallEnd ?? windowEnd,
            inBedMinutes: inBedMin,
            totalAsleepMinutes: totalAsleep,
            deepMinutes: deepMin,
            remMinutes: remMin,
            coreMinutes: coreMin,
            awakeMinutes: awakeMin,
            efficiencyPct: efficiency,
            restorativePct: restorative,
            isPrimary: totalAsleep >= 120 // Sessiones de al menos 2h son primarias
        )
    }

    // MARK: - 5. Strict Noise-Filtered VFC (HRV SDNN) Processing

    public func extractNocturnalHRV(sleepSession: NightlySleepSession?, targetDay: Date) async -> ProcessedNightlyHRV {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return ProcessedNightlyHRV(medianHRV: 0, weightedHRV: 0, sampleCount: 0, confidence: .low)
        }

        let calendar = Calendar.current
        var searchStart = sleepSession?.startDate ?? calendar.date(byAdding: .hour, value: -12, to: targetDay)!
        var searchEnd = sleepSession?.endDate ?? targetDay
        var isColdStartMorning = false

        // Si no durmiÃ³ con el reloj, buscar en los primeros 30 min tras despertarse
        if sleepSession == nil || sleepSession!.totalAsleepMinutes < 60 {
            isColdStartMorning = true
            searchStart = targetDay
            searchEnd = calendar.date(byAdding: .minute, value: 30, to: targetDay)!
        }

        let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: searchEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let msUnit = HKUnit.secondUnit(with: .milli)
        let values: [(date: Date, val: Double)] = samples.map { ($0.startDate, $0.quantity.doubleValue(for: msUnit)) }

        guard !values.isEmpty else {
            return ProcessedNightlyHRV(medianHRV: 0, weightedHRV: 0, sampleCount: 0, confidence: .low)
        }

        // 1. Calcular Mediana
        let sortedValues = values.map { $0.val }.sorted()
        let median: Double
        if sortedValues.count % 2 == 0 {
            median = (sortedValues[sortedValues.count / 2 - 1] + sortedValues[sortedValues.count / 2]) / 2.0
        } else {
            median = sortedValues[sortedValues.count / 2]
        }

        // 2. Media Ponderada: 60% al Ãºltimo tercio de la noche, 40% a los dos primeros tercios
        let sessionDuration = searchEnd.timeIntervalSince(searchStart)
        let lastThirdThreshold = searchStart.addingTimeInterval(sessionDuration * (2.0 / 3.0))

        var earlySamples: [Double] = []
        var lateSamples: [Double] = []

        for item in values {
            if item.date >= lastThirdThreshold {
                lateSamples.append(item.val)
            } else {
                earlySamples.append(item.val)
            }
        }

        let weighted: Double
        if !lateSamples.isEmpty && !earlySamples.isEmpty {
            let earlyMean = earlySamples.reduce(0, +) / Double(earlySamples.count)
            let lateMean = lateSamples.reduce(0, +) / Double(lateSamples.count)
            weighted = (earlyMean * 0.40) + (lateMean * 0.60)
        } else {
            weighted = median
        }

        let confidence: DataConfidence = isColdStartMorning ? .low : (samples.count >= 4 ? .high : .medium)

        return ProcessedNightlyHRV(
            medianHRV: median,
            weightedHRV: weighted,
            sampleCount: samples.count,
            confidence: confidence
        )
    }

    // MARK: - 6. RHR and Sleeping Min HR (Nadir Detection)

    public func extractNocturnalHeartRates(sleepSession: NightlySleepSession?, targetDay: Date) async -> ProcessedNightlyHeartRate {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        
        // 1. Resting Heart Rate de Apple Salud
        var rhrValue: Double = 0.0
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -1, to: targetDay)!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let rhrSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: rhrType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, _ in
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(query)
            }
            if let first = rhrSamples.first {
                rhrValue = first.quantity.doubleValue(for: bpmUnit)
            }
        }

        // 2. Continuous HR during Sleep for Nadir (MÃ­nimo Nocturno)
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let sleep = sleepSession else {
            return ProcessedNightlyHeartRate(restingHR: rhrValue, sleepingMinHR: rhrValue, sleepingMinHRTimestamp: nil, nadirElapsedFraction: 0.5)
        }

        let predicate = HKQuery.predicateForSamples(withStart: sleep.startDate, end: sleep.endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let hrSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        var minHR: Double = 999.0
        var minHRDate: Date? = nil

        for s in hrSamples {
            let bpm = s.quantity.doubleValue(for: bpmUnit)
            if bpm > 30.0 && bpm < minHR { // Filter out sensor dropouts below 30 bpm
                minHR = bpm
                minHRDate = s.startDate
            }
        }

        if minHR == 999.0 {
            minHR = rhrValue > 0 ? rhrValue : 50.0
            minHRDate = sleep.startDate.addingTimeInterval(sleep.endDate.timeIntervalSince(sleep.startDate) * 0.5)
        }

        let totalNightDuration = sleep.endDate.timeIntervalSince(sleep.startDate)
        let nadirFraction: Double
        if totalNightDuration > 0, let nadirDate = minHRDate {
            nadirFraction = min(max(nadirDate.timeIntervalSince(sleep.startDate) / totalNightDuration, 0.0), 1.0)
        } else {
            nadirFraction = 0.5
        }

        return ProcessedNightlyHeartRate(
            restingHR: rhrValue > 0 ? rhrValue : minHR,
            sleepingMinHR: minHR,
            sleepingMinHRTimestamp: minHRDate,
            nadirElapsedFraction: nadirFraction
        )
    }

    // MARK: - 7. Secondary Nocturnal Vitals (Wrist Temp, Resp Rate, SpO2)

    public func extractNocturnalVitals(sleepSession: NightlySleepSession?) async -> ProcessedNocturnalVitals {
        let calendar = Calendar.current
        let start = sleepSession?.startDate ?? calendar.date(byAdding: .hour, value: -10, to: Date())!
        let end = sleepSession?.endDate ?? Date()

        // 1. Wrist Temp Delta
        var tempDelta: Double = 0.0
        if let tempType = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let degC = HKUnit.degreeCelsius()
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: tempType, predicate: predicate, limit: 10, sortDescriptors: nil) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(query)
            }
            if let first = samples.first {
                tempDelta = first.quantity.doubleValue(for: degC)
            }
        }

        // 2. Respiratory Rate
        var meanResp: Double = 14.5
        if let respType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let countUnit = HKUnit.count().unitDivided(by: .minute())
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: respType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(query)
            }
            if !samples.isEmpty {
                let vals = samples.map { $0.quantity.doubleValue(for: countUnit) }
                meanResp = vals.reduce(0, +) / Double(vals.count)
            }
        }

        // 3. SpO2 Mean and Min
        var meanSpO2: Double = 98.0
        var minSpO2: Double = 95.0
        if let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let pctUnit = HKUnit.percent()
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: spo2Type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                    continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(query)
            }
            if !samples.isEmpty {
                let vals = samples.map { $0.quantity.doubleValue(for: pctUnit) * 100.0 }
                meanSpO2 = vals.reduce(0, +) / Double(vals.count)
                minSpO2 = vals.min() ?? 95.0
            }
        }

        return ProcessedNocturnalVitals(
            tempDeltaCelsius: tempDelta,
            meanRespiratoryRate: meanResp,
            meanSpO2: meanSpO2,
            minSpO2: minSpO2
        )
    }

    // MARK: - 8. Activity, Steps and Workouts with 5-Zone HR Distribution

    public func extractDailyActivity(targetDay: Date) async -> (steps: Int, cals: Double, workouts: [WorkoutSummary]) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: targetDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        // 1. Steps
        var totalSteps = 0
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let countUnit = HKUnit.count()
            let sum: Double = await withCheckedContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                    continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: countUnit) ?? 0.0)
                }
                healthStore.execute(query)
            }
            totalSteps = Int(sum)
        }

        // 2. Active Calories
        var activeCals = 0.0
        if let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let kcalUnit = HKUnit.kilocalorie()
            let sum: Double = await withCheckedContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                    continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: kcalUnit) ?? 0.0)
                }
                healthStore.execute(query)
            }
            activeCals = sum
        }

        // 3. Workouts
        var workoutItems: [WorkoutSummary] = []
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let rawWorkouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 10, sortDescriptors: [sortDescriptor]) { _, res, _ in
                continuation.resume(returning: (res as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        for w in rawWorkouts {
            let durMin = Int(w.duration / 60.0)
            let kcal = Int(w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0.0)
            let (icon, name) = workoutMetadata(for: w.workoutActivityType)

            // Query HR during this workout
            let hrDistribution = await computeWorkoutHRZones(workout: w, age: 26)

            workoutItems.append(WorkoutSummary(
                id: w.uuid,
                activityType: w.workoutActivityType,
                name: name,
                sfSymbol: icon,
                startDate: w.startDate,
                durationMinutes: durMin,
                activeCalories: kcal,
                avgHeartRate: Int(hrDistribution.avgHeartRate),
                maxHeartRate: Int(hrDistribution.maxHeartRate)
            ))
        }

        return (totalSteps, activeCals, workoutItems)
    }

    // MARK: - 9. 5-Zone Heart Rate Distribution & Streaming Strain

    public func computeWorkoutHRZones(workout: HKWorkout, age: Int = 26) async -> WorkoutZoneDistribution {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return WorkoutZoneDistribution(workoutId: workout.uuid, activityType: workout.workoutActivityType, durationMinutes: workout.duration / 60.0, activeCalories: 0, z1Minutes: 0, z2Minutes: 0, z3Minutes: 0, z4Minutes: 0, z5Minutes: 0, avgHeartRate: 130, maxHeartRate: 165)
        }

        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let maxHR = Double(208 - Int(0.7 * Double(age))) // Tanaka formula
        var z1Count = 0, z2Count = 0, z3Count = 0, z4Count = 0, z5Count = 0
        var totalBpm = 0.0
        var peakBpm = 0.0

        for s in samples {
            let bpm = s.quantity.doubleValue(for: bpmUnit)
            totalBpm += bpm
            if bpm > peakBpm { peakBpm = bpm }

            let pct = bpm / maxHR
            if pct >= 0.90 {
                z5Count += 1
            } else if pct >= 0.80 {
                z4Count += 1
            } else if pct >= 0.70 {
                z3Count += 1
            } else if pct >= 0.60 {
                z2Count += 1
            } else if pct >= 0.50 {
                z1Count += 1
            }
        }

        let totalSamples = max(samples.count, 1)
        let durMin = workout.duration / 60.0
        let fraction = durMin / Double(totalSamples)

        return WorkoutZoneDistribution(
            workoutId: workout.uuid,
            activityType: workout.workoutActivityType,
            durationMinutes: durMin,
            activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            z1Minutes: Double(z1Count) * fraction,
            z2Minutes: Double(z2Count) * fraction,
            z3Minutes: Double(z3Count) * fraction,
            z4Minutes: Double(z4Count) * fraction,
            z5Minutes: Double(z5Count) * fraction,
            avgHeartRate: totalBpm / Double(totalSamples),
            maxHeartRate: peakBpm
        )
    }

    private func workoutMetadata(for type: HKWorkoutActivityType) -> (icon: String, name: String) {
        switch type {
        case .running: return ("figure.run", "Carrera al aire libre")
        case .cycling: return ("figure.outdoor.cycle", "Ciclismo")
        case .swimming: return ("figure.pool.swim", "Natación")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return ("dumbbell.fill", "Entrenamiento de Fuerza")
        case .highIntensityIntervalTraining: return ("flame.fill", "HIIT")
        case .walking: return ("figure.walk", "Caminata")
        case .yoga: return ("figure.mind.and.body", "Yoga")
        case .pilates: return ("figure.pilates", "Pilates")
        default: return ("figure.cross.training", "Entrenamiento Funcional")
        }
    }
}
#endif

// MARK: - Pure WHOOP + Bevel Physiology Calculator for Apple Watch / HealthKit Snapshots

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
        ageYears: Double = 19.4,
        sex: BiologicalSexProfile = .male,
        weightKg: Double = 58.8,
        heightCm: Double = 175.0,
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

public enum WhoopHealthKitPhysiologyCalculator {
    public static func computeMaxHeartRate(profile: UserPhysiologyProfileConfig, observedPeakBpm: Int = 0) -> Int {
        if let override = profile.maxHrOverride {
            return min(max(override, 130), 225)
        }
        let tanaka = Int((208.0 - 0.7 * profile.ageYears).rounded())
        return min(max(max(tanaka, observedPeakBpm), 130), 225)
    }

    public static func computeBmrKcalPerDay(profile: UserPhysiologyProfileConfig) -> Int {
        let w = profile.weightKg
        let h = profile.heightCm
        let a = profile.ageYears
        let bmr: Double
        switch profile.sex {
        case .male: bmr = 88.362 + 13.397 * w + 4.799 * h - 5.677 * a
        case .female: bmr = 447.593 + 9.247 * w + 3.098 * h - 4.330 * a
        case .nonBinary: bmr = 267.9775 + 11.322 * w + 3.9485 * h - 5.0035 * a
        }
        return max(Int(bmr.rounded()), 1000)
    }

    public static func computeRecoveryPercent(
        hrvMs: Double,
        rhrBpm: Double,
        respRpm: Double,
        spo2Pct: Double,
        wristTempDeltaC: Double,
        sleepScorePct: Int,
        hrvMean: Double = 72.0,
        hrvSigma: Double = 8.0,
        rhrMean: Double = 49.5,
        rhrSigma: Double = 2.5,
        respMean: Double = 15.2,
        respSigma: Double = 0.6
    ) -> Int {
        let zHrv = (hrvMs - hrvMean) / max(hrvSigma, 1.0)
        let zRhr = (rhrMean - rhrBpm) / max(rhrSigma, 0.8)
        let zSleep = (Double(sleepScorePct) / 100.0 - 0.85) / 0.12
        let zResp = (respMean - respRpm) / max(respSigma, 0.3)
        let zTemp = -abs(wristTempDeltaC) / 1.0
        let compositeZ = 0.55 * zHrv + 0.20 * zRhr + 0.15 * zSleep + 0.05 * zResp + 0.05 * zTemp
        var score = 100.0 / (1.0 + exp(-1.6 * (compositeZ + 0.20)))
        if spo2Pct < 95.0 {
            score -= (95.0 - spo2Pct) * 1.6
        }
        if wristTempDeltaC > 0.5 && zRhr < -1.0 {
            score *= 0.75
        }
        return min(max(Int(score.rounded()), 1), 99)
    }

    public static func computeEffortPercentFromZones(
        profile: UserPhysiologyProfileConfig,
        rhrBpm: Double,
        zoneMinutes: [Double]
    ) -> Int {
        let b = profile.sex.banisterB
        let floorRate = 0.10 * 0.64 * exp(b * 0.10)
        let mids = [0.55, 0.65, 0.75, 0.85, 0.95]
        var trimp = 0.0
        for (idx, mins) in zoneMinutes.prefix(5).enumerated() where mins > 0 {
            let x = mids[idx]
            let rate = x * 0.64 * exp(b * x)
            trimp += mins * max(rate - floorRate, 0.0)
        }
        let maxRefTrimp = 320.0 * (b / 1.92)
        let pct = 100.0 * log(1.0 + max(trimp, 1.0)) / log(1.0 + maxRefTrimp)
        return min(max(Int(pct.rounded()), 1), 100)
    }
}


