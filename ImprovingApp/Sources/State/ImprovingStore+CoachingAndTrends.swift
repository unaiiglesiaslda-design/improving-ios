import Foundation
import Combine
import SwiftUI
import UIKit
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

extension ImprovingStore {
    // MARK: - 4-Hour Time-Aware Section Coaching Engine

    func currentFourHourBlockInfo(for date: Date = Date()) -> (blockIndex: Int, slotId: String, generatedAtLabel: String, nextUpdateLabel: String) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let blockIdx = hour / 4 // 0..5 -> 00:00, 04:00, 08:00, 12:00, 16:00, 20:00
        let todayIso = isoFormatter.string(from: date)
        let generatedAt = String(format: "%02d:%02d", hour, minute)
        let nextHour = ((blockIdx + 1) * 4) % 24
        let nextUpdate = String(format: "%02d:00", nextHour)
        return (blockIdx, "\(todayIso)_b\(blockIdx)", generatedAt, nextUpdate)
    }

    func coachingSlotKey(for section: CoachingSection, now: Date = Date()) -> String {
        let info = currentFourHourBlockInfo(for: now)
        return "\(section.rawValue)_\(info.slotId)_\(selectedDateIso)_r\(dataRevision)"
    }

    func coachingCard(for section: CoachingSection) -> SectionCoachingCard? {
        sectionCoachingCache[coachingSlotKey(for: section)]
    }

    func isLoadingCoaching(for section: CoachingSection) -> Bool {
        loadingCoachingSections.contains(section)
    }

    func buildSectionFacts(for section: CoachingSection) -> (facts: [String], hasData: Bool) {
        let av = dataAvailability
        let d = currentDaySummary
        var facts: [String] = []

        switch section {
        case .hoy:
            if av.hasRecoveryData { facts.append("Recuperación \(recoveryPercent)% (\(recoveryStatusText))") }
            if av.hasStrainData { facts.append("Esfuerzo \(strainPercent)% (Strain \(String(format: "%.1f", strain21))/21, objetivo \(effortTargetRangeText))") }
            if av.hasSleepData { facts.append("Sueño \(sleepDurationText) con puntuación \(sleepPercent)%") }
            if av.hasHrvData { facts.append(String(format: "VFC nocturna %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs)) }
            if av.hasRestingHrData { facts.append(String(format: "FCR durmiendo %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm)) }
            if av.hasEnergyData { facts.append("Batería de energía al \(energyPercent)%") }
            if av.hasStressData {
                if dayOffset == 0 && !stressSamplesToday.isEmpty {
                    facts.append("Estrés actual \(currentStressScore)/100 (\(stressStatusLabel)) con media diaria \(stressAvg ?? stressScore)/100")
                } else {
                    facts.append("Estrés medio \(stressScore)/100 (\(stressStatusLabel))")
                }
            }
            if let steps = stepsCount { facts.append("\(steps) pasos acumulados") }
            return (facts, av.hasAnyRecordedData)

        case .esfuerzo:
            if av.hasStrainData { facts.append("Esfuerzo diario \(strainPercent)% (Strain \(String(format: "%.1f", strain21))/21, estado \(strainStatusText))") }
            if av.hasRecoveryData { facts.append("Rango objetivo óptimo según recuperación \(recoveryPercent)%: \(effortTargetRangeText)") }
            if let kcal = d?.activeKcal { facts.append("Calorías activas: \(kcal) kcal") }
            if let steps = stepsCount { facts.append("Pasos: \(steps)") }
            if let hr = liveHrBpm { facts.append("FC diurna media: \(hr) ppm") }
            if !workoutsToday.isEmpty {
                let wDesc = workoutsToday.map { w in
                    var s = "\(w.title) de \(w.durationMin) min (\(w.strainPct)% esfuerzo"
                    if w.kcal > 0 { s += ", \(w.kcal) kcal" }
                    if w.avgHrBpm > 0 { s += ", FC media \(w.avgHrBpm) ppm" }
                    s += ")"
                    return s
                }.joined(separator: "; ")
                facts.append("Entrenamientos: \(wDesc)")
            }
            let z = d?.hrZoneMinutes ?? []
            if z.reduce(0, +) > 0 {
                facts.append("Minutos por zonas de FC Z1-Z5: \(z.enumerated().map { "Z\($0.offset + 1) \($0.element)m" }.joined(separator: ", "))")
            }
            return (facts, av.hasStrainData || av.hasWorkoutData)

        case .recuperacion:
            if av.hasRecoveryData { facts.append("Recuperación \(recoveryPercent)% (\(recoveryStatusText))") }
            if av.hasHrvData {
                let recentHrv = trailingCalendarSummaries(days: 30).compactMap { $0.summary?.hrvMs }
                let avg30 = recentHrv.isEmpty ? nil : (recentHrv.reduce(0, +) / Double(recentHrv.count))
                if let a = avg30 {
                    facts.append(String(format: "VFC nocturna %.1f ms frente a tu media de 30 días de %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs, a))
                } else {
                    facts.append(String(format: "VFC nocturna %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs))
                }
            }
            if av.hasRestingHrData {
                let recentRhr = trailingCalendarSummaries(days: 30).compactMap { $0.summary?.restingHrBpm }
                let avg30 = recentRhr.isEmpty ? nil : (recentRhr.reduce(0, +) / Double(recentRhr.count))
                if let a = avg30 {
                    facts.append(String(format: "FC en reposo durmiendo %.1f ppm frente a tu media de 30 días de %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm, a))
                } else {
                    facts.append(String(format: "FC en reposo durmiendo %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm))
                }
            }
            if av.hasRespData { facts.append(String(format: "Frecuencia respiratoria %.1f rpm", locale: Locale(identifier: "es_ES"), respRateRpm)) }
            if let sp = spo2Value { facts.append(String(format: "SpO2 nocturna %.1f%%", locale: Locale(identifier: "es_ES"), sp)) }
            if let t = wristTempAbsoluteC {
                let dStr = d?.wristTempDeltaC.map { String(format: " (desviación %+.1f °C)", locale: Locale(identifier: "es_ES"), $0) } ?? ""
                facts.append(String(format: "Temperatura muñeca %.1f °C%@", locale: Locale(identifier: "es_ES"), t, dStr))
            }
            return (facts, av.hasRecoveryData || av.hasHrvData || av.hasRestingHrData)

        case .sueno:
            let sess = d?.sleepSession
            if av.hasSleepData { facts.append("Puntuación del sueño \(sleepPercent)% (\(sleepStatusText)), duración real dormida \(sleepDurationText)") }
            if let bed = d?.inBedMinutes, bed > 0 { facts.append("Tiempo en cama \(sleepInBedText)") }
            if let s = sess?.startTimeLabel, let e = sess?.endTimeLabel { facts.append("Horario real: acostado \(s) hasta despertar \(e)") }
            if let eff = sess?.efficiencyPct { facts.append("Eficiencia del sueño \(eff)%") }
            if let deep = d?.deepMinutes, deep > 0 { facts.append("Sueño profundo \(deep) min") }
            if let rem = d?.remMinutes, rem > 0 { facts.append("Sueño REM \(rem) min") }
            if let lat = sess?.latencyMinutes { facts.append("Latencia para dormirse \(lat) min") }
            if let dip = sess?.hrDipPct { facts.append(String(format: "Disminución nocturna de FC %.1f%%", locale: Locale(identifier: "es_ES"), dip)) }
            if let debt = d?.sleepDebtMinutes, debt > 0 { facts.append("Deuda de sueño acumulada \(debt) min") }
            return (facts, av.hasSleepData)

        case .estres:
            let samples = stressSamplesToday
            if av.hasStressData {
                facts.append("Estrés actual \(displayStressScore)/100 (\(stressStatusLabel)), media diaria \(stressAvg ?? stressScore)/100 con \(samples.count) muestras reales")
            }
            if let mx = stressMax, let mn = stressMin { facts.append("Rango del día: mínimo \(mn) y pico máximo \(mx)") }
            if let peak = samples.max(by: { $0.value < $1.value }) {
                let hhmm = String(format: "%02d:%02d", (peak.minuteOfDay / 60) % 24, peak.minuteOfDay % 60)
                facts.append("Pico más alto alrededor de las \(hhmm) con \(Int(peak.value.rounded()))/100")
            }
            let stepMin = samples.count > 40 ? 5 : 60
            let highMin = samples.filter { $0.value >= 65 }.count * stepMin
            let lowMin = samples.filter { $0.value < 35 }.count * stepMin
            if !samples.isEmpty {
                facts.append("Tiempo en estrés alto: \(highMin) min; en estrés bajo: \(lowMin / 60) h \(lowMin % 60) min")
            }
            return (facts, av.hasStressData)

        case .energia:
            let samples = energySamplesToday
            if av.hasEnergyData { facts.append("Nivel actual de batería de energía: \(energyPercent)%") }
            if let first = samples.first {
                let t = String(format: "%02d:%02d", (first.minuteOfDay / 60) % 24, first.minuteOfDay % 60)
                facts.append("Inicio continuo a las \(t) desde \(Int(first.value.rounded()))% heredado de la jornada previa")
            }
            if let peak = samples.max(by: { $0.value < $1.value }) {
                let t = String(format: "%02d:%02d", (peak.minuteOfDay / 60) % 24, peak.minuteOfDay % 60)
                facts.append("Pico de recarga de \(Int(peak.value.rounded()))% a las \(t)")
                if let first = samples.first, let last = samples.last {
                    let charged = max(Int((peak.value - first.value).rounded()), 0)
                    let drained = max(Int((peak.value - last.value).rounded()), 0)
                    facts.append("Balance del día: +\(charged)% cargado y -\(drained)% gastado")
                }
            }
            return (facts, av.hasEnergyData)

        case .fitness:
            let last30 = trailingCalendarSummaries(days: 30)
            let w30 = last30.flatMap { $0.summary?.workouts ?? [] }
            let last7 = trailingCalendarSummaries(days: 7)
            let strain7 = last7.compactMap { $0.summary?.strainPct }
            let strMin7 = last7.compactMap { $0.summary?.strengthMinutes }.reduce(0, +)
            if !w30.isEmpty {
                let mins30 = w30.reduce(0) { $0 + $1.durationMin }
                let kcal30 = w30.reduce(0) { $0 + $1.kcal }
                facts.append("Últimos 30 días: \(w30.count) sesiones, \(mins30 / 60) h \(mins30 % 60) min y \(kcal30) kcal")
            }
            if !strain7.isEmpty {
                let avg7 = Int((Double(strain7.reduce(0, +)) / Double(strain7.count)).rounded())
                facts.append("Esfuerzo medio 7 días: \(avg7)%; fuerza 7 días: \(strMin7) min")
            }
            if let vo2 = latestVo2Max { facts.append(String(format: "VO2 máx. %.1f mL/kg·min", locale: Locale(identifier: "es_ES"), vo2)) }
            if let hrr = latestHrRecoveryBpm { facts.append("Recuperación de FC 1 min: \(Int(hrr.rounded())) ppm") }
            if av.hasRecoveryData { facts.append("Recuperación actual para entrenar: \(recoveryPercent)%") }
            if !workoutsToday.isEmpty {
                facts.append("Entrenamientos hoy: \(workoutsToday.map { "\($0.title) \($0.durationMin)m" }.joined(separator: ", "))")
            }
            return (facts, !facts.isEmpty)
        }
    }

    func refreshCoachingIfNeeded(for section: CoachingSection, force: Bool = false) {
        let now = Date()
        let info = currentFourHourBlockInfo(for: now)
        let key = coachingSlotKey(for: section, now: now)
        if !force && sectionCoachingCache[key] != nil { return }

        coachingTasks[section]?.cancel()
        loadingCoachingSections.insert(section)

        let ctx = buildBiometricContextJson()
        let secFacts = buildSectionFacts(for: section)
        let missing = dataAvailability.missingCategoryNames
        let prevHead = lastHeadlineBySection[section] ?? sectionCoachingCache[key]?.headline
        let apiKey = geminiApiKey
        let model = selectedGeminiModel
        let allowCloud = cloudAIEnabled
        let allowKeyless = allowKeylessAIFallback
        let userName = redactPIIFromAI ? "Usuario" : userProfile.userName
        let selIso = selectedDateIso
        let isToday = dayOffset == 0

        coachingTasks[section] = Task { [weak self] in
            let card = await GeminiCoachService.shared.generateSectionCoaching(
                section: section,
                currentDate: now,
                selectedDateIso: selIso,
                isViewingToday: isToday,
                userName: userName,
                biometricContextJson: ctx.json,
                sectionFacts: secFacts.facts,
                missingCategories: missing,
                previousHeadline: prevHead,
                hasSectionData: secFacts.hasData,
                slotKey: key,
                generatedAtLabel: info.generatedAtLabel,
                nextUpdateLabel: info.nextUpdateLabel,
                apiKey: apiKey,
                selectedModel: model,
                allowCloudAI: allowCloud,
                allowKeylessFallback: allowKeyless
            )
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.sectionCoachingCache[key] = card
                self.sectionCoachingTimestamps[key] = Date().timeIntervalSince1970
                self.lastHeadlineBySection[section] = card.headline
                self.loadingCoachingSections.remove(section)
                // Evict oldest entries by real LRU timestamp (never alphabetical, which previously evicted energia/esfuerzo!)
                if self.sectionCoachingCache.count > 35 {
                    let dropCount = self.sectionCoachingCache.count - 35
                    let oldestKeys = self.sectionCoachingCache.keys.sorted { lhs, rhs in
                        (self.sectionCoachingTimestamps[lhs] ?? 0) < (self.sectionCoachingTimestamps[rhs] ?? 0)
                    }.prefix(dropCount)
                    for k in oldestKeys {
                        self.sectionCoachingCache.removeValue(forKey: k)
                        self.sectionCoachingTimestamps.removeValue(forKey: k)
                    }
                }
                self.persistState()
            }
        }
    }

    // MARK: - Trailing Calendar Days Helper (Sparse, Zero-Fabrication!)

    func trailingCalendarSummaries(days: Int, endingAt endDate: Date? = nil) -> [(iso: String, summary: RealBiometricDaySummary?)] {
        let anchor = Calendar.current.startOfDay(for: endDate ?? selectedDate)
        return (0..<days).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: anchor) else { return nil }
            let iso = isoFormatter.string(from: d)
            return (iso, activeHistory[iso])
        }
    }

    func buildTrendItem(
        id: String,
        title: String,
        currentValue: Double?,
        valueFormatter: (Double) -> String,
        unitText: String,
        series: [Double?],
        bandLow: Double,
        bandHigh: Double,
        lineColorHex: UInt64,
        detailNote: String
    ) -> EffortTrendItem {
        let realVals = series.compactMap { $0 }
        guard let cur = currentValue else {
            return EffortTrendItem(
                id: id,
                title: title,
                valueText: "No hay datos",
                unitText: "",
                statusText: "No hay tendencias disponibles",
                statusTone: .noData,
                points: series,
                bandLow: bandLow,
                bandHigh: bandHigh,
                lineColorHex: lineColorHex,
                detailNote: detailNote,
                hasData: false
            )
        }
        let tone: TrendStatusTone
        let status: String
        if realVals.count < 2 {
            tone = .normal
            status = "Dato registrado"
        } else if cur < bandLow {
            tone = .below
            status = "Debajo de lo normal"
        } else if cur > bandHigh {
            tone = .above
            status = "Por encima de lo normal"
        } else {
            tone = .normal
            status = "Rango normal"
        }
        return EffortTrendItem(
            id: id,
            title: title,
            valueText: valueFormatter(cur),
            unitText: unitText,
            statusText: status,
            statusTone: tone,
            points: series,
            bandLow: bandLow,
            bandHigh: bandHigh,
            lineColorHex: lineColorHex,
            detailNote: detailNote,
            hasData: true
        )
    }

    var effortTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let bmr = Double(WhoopPhysiologyEngine.computeBmrKcalPerDay(profile: userProfile))
        let workoutMinToday: Double? = workoutsToday.isEmpty ? nil : Double(workoutsToday.reduce(0) { $0 + $1.durationMin })
        let totalEnergyToday: Double? = currentDaySummary?.activeKcal.map { Double($0) + bmr }
        let perfDeltaToday: Double? = (currentDaySummary?.strainPct != nil && currentDaySummary?.recoveryPct != nil)
            ? Double(strainPercent) - (optimalEffortRange.lowerBound * 100.0 + optimalEffortRange.upperBound * 100.0) / 2.0
            : nil

        return [
            buildTrendItem(
                id: "t_strain", title: "Puntuación del Esfuerzo",
                currentValue: currentDaySummary?.strainPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.strainPct.map { Double($0) } },
                bandLow: 45, bandHigh: 84, lineColorHex: 0xF5B942,
                detailNote: "Evolución de tu esfuerzo cardiovascular y muscular diario."
            ),
            buildTrendItem(
                id: "t_dur", title: "Duración del ejercicio",
                currentValue: workoutMinToday,
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "min",
                series: window.map { item in
                    guard let ws = item.summary?.workouts, !ws.isEmpty else { return nil }
                    return Double(ws.reduce(0) { $0 + $1.durationMin })
                },
                bandLow: 25, bandHigh: 90, lineColorHex: 0xEC7D42,
                detailNote: "Minutos activos acumulados en tus sesiones."
            ),
            buildTrendItem(
                id: "t_day_hr", title: "FC diurna",
                currentValue: liveHrBpm.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "ppm",
                series: window.map { $0.summary?.liveHrBpm.map { Double($0) } },
                bandLow: 55, bandHigh: 78, lineColorHex: 0xEC7D42,
                detailNote: "Frecuencia cardíaca media durante tus horas de vigilia."
            ),
            buildTrendItem(
                id: "t_kcal", title: "Energía total",
                currentValue: totalEnergyToday,
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "kcal",
                series: window.map { $0.summary?.activeKcal.map { Double($0) + bmr } },
                bandLow: bmr + 300, bandHigh: bmr + 1100, lineColorHex: 0xEC7D42,
                detailNote: "Suma de metabolismo basal y energía activa registrada."
            ),
            buildTrendItem(
                id: "t_steps", title: "Número de pasos",
                currentValue: stepsCount.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "",
                series: window.map { $0.summary?.stepsCount.map { Double($0) } },
                bandLow: 7000, bandHigh: 13000, lineColorHex: 0xEC7D42,
                detailNote: "Pasos reales acumulados diariamente."
            ),
            buildTrendItem(
                id: "t_perf", title: "Rendimiento del Esfuerzo",
                currentValue: perfDeltaToday,
                valueFormatter: { String(format: "%+.0f", $0) }, unitText: "%",
                series: window.map { item in
                    guard let st = item.summary?.strainPct, item.summary?.recoveryPct != nil else { return nil }
                    let r = personalizedEffortTarget(for: item.iso, includeCardioLoad: false).range
                    return Double(st) - (r.lowerBound + r.upperBound) * 50.0
                },
                bandLow: -12, bandHigh: 14, lineColorHex: 0x7FA8F8,
                detailNote: "Desviación frente a tu zona óptima según recuperación."
            )
        ]
    }

    /// Returns Bevel-style 60-day personal normal range for a Health Monitor vital (falling back to clinical
    /// age/sex/height/weight norms when fewer than 5 real readings exist in the trailing 60-day window).
    func personalVitalNormalBand(for kind: HealthMetricKind) -> (low: Double, high: Double, isPersonal: Bool) {
        ensureDerivedCacheFresh()
        if let hit = cachedVitalBands[kind] {
            return hit
        }
        let window60 = trailingCalendarSummaries(days: 60)
        let extractor: (RealBiometricDaySummary) -> Double? = { d in
            switch kind {
            case .respiratoryRate: return d.respRateRpm
            case .restingHeartRate: return d.restingHrBpm
            case .hrv: return d.hrvMs
            case .oxygenSaturation: return d.spo2Percent
            case .wristTemperature:
                return d.wristTempAbsoluteC ?? d.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) }
            case .sleepDuration:
                return d.asleepMinutes.map { Double($0) / 60.0 }
            }
        }
        // Prefer strictly prior days when >= 7 prior days exist so today's anomaly doesn't mask itself
        let priorOnly = window60.dropLast().compactMap { $0.summary.flatMap(extractor) }
        let pool = priorOnly.count >= 7 ? priorOnly : window60.compactMap { $0.summary.flatMap(extractor) }
        let band = WhoopPhysiologyEngine.computePersonalVitalNormalBand(
            kind: kind,
            trailingValues: pool,
            profile: userProfile
        )
        cachedVitalBands[kind] = band
        return band
    }

    var recoveryTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let hrvBand = personalVitalNormalBand(for: .hrv)
        let rhrBand = personalVitalNormalBand(for: .restingHeartRate)
        let respBand = personalVitalNormalBand(for: .respiratoryRate)
        let spo2Band = personalVitalNormalBand(for: .oxygenSaturation)
        let tempBand = personalVitalNormalBand(for: .wristTemperature)
        return [
            buildTrendItem(
                id: "r_rec", title: "Puntuación de Recuperación",
                currentValue: currentDaySummary?.recoveryPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.recoveryPct.map { Double($0) } },
                bandLow: 55, bandHigh: 92, lineColorHex: 0x3BD671,
                detailNote: "Capacidad de tu sistema nervioso autónomo para asimilar carga."
            ),
            buildTrendItem(
                id: "r_hrv", title: "VFC en reposo",
                currentValue: currentDaySummary?.hrvMs,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "ms",
                series: window.map { $0.summary?.hrvMs },
                bandLow: hrvBand.low, bandHigh: hrvBand.high, lineColorHex: 0x3BD671,
                detailNote: "Variabilidad de la frecuencia cardíaca consolidada durante el sueño."
            ),
            buildTrendItem(
                id: "r_rhr", title: "FC en reposo",
                currentValue: currentDaySummary?.restingHrBpm,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "ppm",
                series: window.map { $0.summary?.restingHrBpm },
                bandLow: rhrBand.low, bandHigh: rhrBand.high, lineColorHex: 0x3BD671,
                detailNote: "Frecuencia cardíaca media sostenida durante el descanso nocturno."
            ),
            buildTrendItem(
                id: "r_resp", title: "Frecuencia respiratoria",
                currentValue: currentDaySummary?.respRateRpm,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "rpm",
                series: window.map { $0.summary?.respRateRpm },
                bandLow: respBand.low, bandHigh: respBand.high, lineColorHex: 0x3BD671,
                detailNote: "Respiraciones por minuto registradas durante el sueño."
            ),
            buildTrendItem(
                id: "r_spo2", title: "Saturación de oxígeno",
                currentValue: currentDaySummary?.spo2Percent,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "%",
                series: window.map { $0.summary?.spo2Percent },
                bandLow: spo2Band.low, bandHigh: spo2Band.high, lineColorHex: 0x3BD671,
                detailNote: "Porcentaje de saturación capilar periférica de oxígeno."
            ),
            buildTrendItem(
                id: "r_temp", title: "Temperatura de la muñeca",
                currentValue: wristTempAbsoluteC,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "°C",
                series: window.map { item in
                    item.summary?.wristTempAbsoluteC ?? item.summary?.wristTempDeltaC.map { 35.8 + $0 }
                },
                bandLow: tempBand.low, bandHigh: tempBand.high, lineColorHex: 0x3BD671,
                detailNote: "Temperatura media de la piel durante la noche anterior."
            )
        ]
    }

    var sleepTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let hmFmt: (Double) -> String = { mins in
            let m = Int(mins.rounded())
            return "\(m / 60) h \(m % 60) min"
        }
        return [
            buildTrendItem(
                id: "s_score", title: "Puntuación del Sueño",
                currentValue: currentDaySummary?.sleepPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.sleepPct.map { Double($0) } },
                bandLow: 75, bandHigh: 96, lineColorHex: 0xA78BFA,
                detailNote: "Puntuación combinada de duración, eficiencia y fases reparadoras."
            ),
            buildTrendItem(
                id: "s_dur", title: "Duración del sueño",
                currentValue: currentDaySummary?.asleepMinutes.map { Double($0) },
                valueFormatter: hmFmt, unitText: "",
                series: window.map { $0.summary?.asleepMinutes.map { Double($0) } },
                bandLow: norms.sleepLowHours * 60.0, bandHigh: norms.sleepHighHours * 60.0, lineColorHex: 0x93A8F8,
                detailNote: "Horas netas de sueño excluyendo despertares nocturnos."
            ),
            buildTrendItem(
                id: "s_rem", title: "Sueño REM",
                currentValue: currentDaySummary?.remMinutes.flatMap { $0 > 0 ? Double($0) : nil },
                valueFormatter: hmFmt, unitText: "",
                series: window.map { $0.summary?.remMinutes.flatMap { $0 > 0 ? Double($0) : nil } },
                bandLow: 70, bandHigh: 130, lineColorHex: 0x93A8F8,
                detailNote: "Tiempo en fase de movimiento ocular rápido (REM)."
            ),
            buildTrendItem(
                id: "s_deep", title: "Sueño profundo",
                currentValue: currentDaySummary?.deepMinutes.flatMap { $0 > 0 ? Double($0) : nil },
                valueFormatter: hmFmt, unitText: "",
                series: window.map { $0.summary?.deepMinutes.flatMap { $0 > 0 ? Double($0) : nil } },
                bandLow: 55, bandHigh: 115, lineColorHex: 0x93A8F8,
                detailNote: "Sueño de ondas lentas restaurador."
            ),
            buildTrendItem(
                id: "s_dip", title: "Disminución de la FC",
                currentValue: currentDaySummary?.sleepSession?.hrDipPct,
                valueFormatter: { String(format: "%.0f", $0) }, unitText: "%",
                series: window.map { $0.summary?.sleepSession?.hrDipPct },
                bandLow: 10, bandHigh: 20, lineColorHex: 0x93A8F8,
                detailNote: "Descenso de la frecuencia cardíaca nocturna respecto al día."
            ),
            buildTrendItem(
                id: "s_eff", title: "Eficiencia del sueño",
                currentValue: currentDaySummary?.sleepSession?.efficiencyPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.sleepSession?.efficiencyPct.map { Double($0) } },
                bandLow: 85, bandHigh: 98, lineColorHex: 0x3BD671,
                detailNote: "Porcentaje del tiempo en cama que pasaste dormido."
            ),
            buildTrendItem(
                id: "s_lat", title: "Tiempo que tardas en dormirte",
                currentValue: currentDaySummary?.sleepSession?.latencyMinutes.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded())) min" }, unitText: "",
                series: window.map { $0.summary?.sleepSession?.latencyMinutes.map { Double($0) } },
                bandLow: 5, bandHigh: 25, lineColorHex: 0x93A8F8,
                detailNote: "Latencia desde que te acuestas hasta conciliar el sueño."
            )
        ]
    }

    var stressTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let sleepStressToday: Double? = {
            guard let sw = sleepWindowMinutes else { return nil }
            let vals = stressSamplesToday.filter { sw.contains($0.minuteOfDay) }.map(\.value)
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }()
        return [
            buildTrendItem(
                id: "st_score", title: "Puntuación del Estrés",
                currentValue: stressAvg.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "",
                series: window.map { $0.summary?.stressScore.map { Double($0) } },
                bandLow: 15, bandHigh: 45, lineColorHex: 0x56D5C6,
                detailNote: "Nivel medio diario de estrés fisiológico."
            ),
            buildTrendItem(
                id: "st_sleep", title: "Estrés del sueño",
                currentValue: sleepStressToday,
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "",
                series: window.map { item in
                    guard let s = item.summary, !s.stressSamples5m.isEmpty else { return nil }
                    let night: [Double]
                    if let sess = s.sleepSession, let stEp = sess.startEpochSec, let enEp = sess.endEpochSec, enEp > stEp {
                        let byEpoch = s.stressSamples5m.filter { pt in
                            guard let ep = pt.epochSec else { return false }
                            return ep >= stEp && ep <= enEp
                        }.map(\.value)
                        if !byEpoch.isEmpty {
                            night = byEpoch
                        } else {
                            let sMin = Int((stEp % 86400) / 60)
                            let eMin = Int((enEp % 86400) / 60)
                            night = s.stressSamples5m.filter { pt in
                                sMin <= eMin ? (pt.minuteOfDay >= sMin && pt.minuteOfDay <= eMin) : (pt.minuteOfDay >= sMin || pt.minuteOfDay <= eMin)
                            }.map(\.value)
                        }
                    } else {
                        night = s.stressSamples5m.filter { $0.minuteOfDay < 480 }.map(\.value)
                    }
                    guard !night.isEmpty else { return nil }
                    return night.reduce(0, +) / Double(night.count)
                },
                bandLow: 2, bandHigh: 18, lineColorHex: 0x56D5C6,
                detailNote: "Activación simpática durante tus horas de sueño."
            )
        ]
    }

    func trendExtractor(for trendId: String) -> (RealBiometricDaySummary) -> Double? {
        let bmr = Double(WhoopPhysiologyEngine.computeBmrKcalPerDay(profile: userProfile))
        switch trendId {
        case "t_strain":
            return { $0.strainPct.map { Double($0) } }
        case "t_dur":
            return { d in d.workouts.isEmpty ? nil : Double(d.workouts.reduce(0) { $0 + $1.durationMin }) }
        case "t_day_hr":
            return { $0.liveHrBpm.map { Double($0) } }
        case "t_kcal":
            return { $0.activeKcal.map { Double($0) + bmr } }
        case "t_steps":
            return { $0.stepsCount.map { Double($0) } }
        case "t_perf":
            return { [weak self] d in
                guard let st = d.strainPct, let rec = d.recoveryPct else { return nil }
                let r = self?.personalizedEffortTarget(for: d.dateIso, includeCardioLoad: false).range ?? WhoopPhysiologyEngine.optimalTargetRange(for: rec)
                return Double(st) - (r.lowerBound + r.upperBound) * 50.0
            }
        case "r_rec":
            return { $0.recoveryPct.map { Double($0) } }
        case "r_hrv":
            return { $0.hrvMs }
        case "r_rhr":
            return { $0.restingHrBpm }
        case "r_resp":
            return { $0.respRateRpm }
        case "r_spo2":
            return { $0.spo2Percent }
        case "r_temp":
            return { $0.wristTempAbsoluteC ?? $0.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) } }
        case "s_score":
            return { $0.sleepPct.map { Double($0) } }
        case "s_dur":
            return { $0.asleepMinutes.map { Double($0) } }
        case "s_rem":
            return { $0.remMinutes.flatMap { $0 > 0 ? Double($0) : nil } }
        case "s_deep":
            return { $0.deepMinutes.flatMap { $0 > 0 ? Double($0) : nil } }
        case "s_dip":
            return { $0.sleepSession?.hrDipPct }
        case "s_eff":
            return { $0.sleepSession?.efficiencyPct.map { Double($0) } }
        case "s_lat":
            return { $0.sleepSession?.latencyMinutes.map { Double($0) } }
        case "st_score":
            return { $0.stressScore.map { Double($0) } }
        case "st_sleep":
            return { d in
                guard !d.stressSamples5m.isEmpty else { return nil }
                let night = d.stressSamples5m.filter { $0.minuteOfDay < 480 }.map(\.value)
                guard !night.isEmpty else { return nil }
                return night.reduce(0, +) / Double(night.count)
            }
        default:
            return { $0.recoveryPct.map { Double($0) } }
        }
    }

    // MARK: - Paginated Time-Window Metric Series (7 d | 30 d | 3 M | 6 M | 1 A with < / > arrows!)

    func metricWindowSeries(
        for kind: HealthMetricKind,
        spanDays: Int,
        windowPageOffset: Int
    ) -> MetricWindowSeries {
        let cal = Calendar.current
        let anchorToday = cal.startOfDay(for: selectedDate)
        let endDate = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchorToday) ?? anchorToday
        let startDate = cal.date(byAdding: .day, value: -(spanDays - 1), to: endDate) ?? endDate

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "es_ES")
        outFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"

        let rangeFmt = DateFormatter()
        rangeFmt.locale = Locale(identifier: "es_ES")
        rangeFmt.dateFormat = spanDays >= 180 ? "d MMM yyyy" : "d MMM"

        var labels: [String] = []
        var values: [Double?] = []
        var realPts: [Double] = []
        labels.reserveCapacity(spanDays)
        values.reserveCapacity(spanDays)

        for i in 0..<spanDays {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let iso = isoFormatter.string(from: d)
            let lbl = outFmt.string(from: d).replacingOccurrences(of: ".", with: "")
            labels.append(lbl)
            let summary = activeHistory[iso]
            let v: Double? = switch kind {
            case .respiratoryRate: summary?.respRateRpm
            case .restingHeartRate: summary?.restingHrBpm
            case .hrv: summary?.hrvMs
            case .oxygenSaturation: summary?.spo2Percent
            case .wristTemperature: summary?.wristTempAbsoluteC ?? summary?.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) }
            case .sleepDuration: summary?.asleepMinutes.map { Double($0) / 60.0 }
            }
            values.append(v)
            if let v { realPts.append(v) }
        }

        let rangeLabel = "\(rangeFmt.string(from: startDate).replacingOccurrences(of: ".", with: "")) – \(rangeFmt.string(from: endDate).replacingOccurrences(of: ".", with: ""))"
        let earliestIso = activeHistory.keys.sorted().first ?? "2020-01-01"
        let earliestDt = isoFormatter.date(from: earliestIso) ?? earliestAvailableDate
        let canBack = startDate > earliestDt

        return MetricWindowSeries(
            dates: labels,
            values: values,
            realPoints: realPts,
            windowRangeLabel: rangeLabel,
            canStepForward: windowPageOffset > 0,
            canStepBackward: canBack
        )
    }

    func customWindowSeries(
        spanDays: Int,
        windowPageOffset: Int,
        extractor: (RealBiometricDaySummary) -> Double?
    ) -> MetricWindowSeries {
        let cal = Calendar.current
        let anchorToday = cal.startOfDay(for: selectedDate)
        let endDate = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchorToday) ?? anchorToday
        let startDate = cal.date(byAdding: .day, value: -(spanDays - 1), to: endDate) ?? endDate

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "es_ES")
        outFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"
        let rangeFmt = DateFormatter()
        rangeFmt.locale = Locale(identifier: "es_ES")
        rangeFmt.dateFormat = spanDays >= 180 ? "d MMM yyyy" : "d MMM"

        var labels: [String] = []
        var values: [Double?] = []
        var realPts: [Double] = []
        for i in 0..<spanDays {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let iso = isoFormatter.string(from: d)
            labels.append(outFmt.string(from: d).replacingOccurrences(of: ".", with: ""))
            let v = activeHistory[iso].flatMap(extractor)
            values.append(v)
            if let v { realPts.append(v) }
        }
        let rangeLabel = "\(rangeFmt.string(from: startDate).replacingOccurrences(of: ".", with: "")) – \(rangeFmt.string(from: endDate).replacingOccurrences(of: ".", with: ""))"
        let earliestIso = activeHistory.keys.sorted().first ?? "2020-01-01"
        let earliestDt = isoFormatter.date(from: earliestIso) ?? earliestAvailableDate
        return MetricWindowSeries(
            dates: labels,
            values: values,
            realPoints: realPts,
            windowRangeLabel: rangeLabel,
            canStepForward: windowPageOffset > 0,
            canStepBackward: startDate > earliestDt
        )
    }

}
