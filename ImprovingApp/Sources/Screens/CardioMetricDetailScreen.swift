import SwiftUI

// MARK: - 3. Cardio & Strength Metric Detail Sheet (All 9 Fitness Subscreens Matching Screenshots 7-33!)

struct CardioMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let route: CardioMetricRoute
    let onBack: () -> Void
    var onOpenWorkout: ((EffortEventItem) -> Void)? = nil

    @State private var currentRoute: CardioMetricRoute = .activitiesDuration
    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0
    @State private var isBarMode: Bool = false
    @State private var selectedActivityFilter: String = "Todas"
    @State private var showActivitySearch: Bool = false
    @State private var activitySearchQuery: String = ""
    @State private var selectedActivityKpi: Int = 0 // 0=Dur, 1=Dist, 2=Elev, 3=Kcal, 4=Pace, 5=Speed, 6=HR, 7=Power, 8=Cadence
    @State private var selectedStrengthKpi: Int = 0 // 0=Series, 1=Volumen, 2=Carga
    @State private var sortNewestFirst: Bool = true
    @State private var selectedZoneIdx: Int = 1
    @State private var muscleModeTab: Int = 2 // 0=Volumen total, 1=Carga muscular, 2=Frescura muscular
    @State private var muscleStateFilter: MuscleFreshnessState? = nil
    @State private var muscleDateOffset: Int = 0
    @State private var selectedMuscleDropdown: String = "Todos los músculos"
    @State private var scrollCollapseSignal: Int = 0

    private var spanDays: Int {
        FitnessRangeControlBar.spanDays(for: selectedRange, anchorDate: store.selectedDate)
    }

    private var windowDates: (start: Date, end: Date, prevStart: Date, prevEnd: Date, isos: [String], prevIsos: [String], shortLabels: [String], rangeTitle: String) {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let end = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchor) ?? anchor
        let start = cal.date(byAdding: .day, value: -(spanDays - 1), to: end) ?? end
        let prevEnd = cal.date(byAdding: .day, value: -1, to: start) ?? start
        let prevStart = cal.date(byAdding: .day, value: -(spanDays - 1), to: prevEnd) ?? prevEnd

        let shortFmt = DateFormatter()
        shortFmt.locale = Locale(identifier: "es_ES")
        shortFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"
        let headerFmt = DateFormatter()
        headerFmt.locale = Locale(identifier: "es_ES")
        headerFmt.dateFormat = "d MMM"
        let yearFmt = DateFormatter()
        yearFmt.locale = Locale(identifier: "es_ES")
        yearFmt.dateFormat = "d MMM yyyy"

        var isos: [String] = []
        var prevIsos: [String] = []
        var labels: [String] = []
        for i in 0..<spanDays {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                isos.append(store.isoFormatter.string(from: d))
                labels.append(shortFmt.string(from: d).replacingOccurrences(of: ".", with: ""))
            }
            if let pd = cal.date(byAdding: .day, value: i, to: prevStart) {
                prevIsos.append(store.isoFormatter.string(from: pd))
            }
        }
        let rTitle = "\(headerFmt.string(from: start).replacingOccurrences(of: ".", with: "")) – \(yearFmt.string(from: end).replacingOccurrences(of: ".", with: ""))"
        return (start, end, prevStart, prevEnd, isos, prevIsos, labels, rTitle)
    }

    private var availableActivityNames: [String] {
        let names = Set(store.activeHistory.values.flatMap { $0.workouts.map(\.title) })
        return ["Todas"] + names.sorted()
    }

    private func filterWorkouts(_ list: [EffortEventItem]) -> [EffortEventItem] {
        if selectedActivityFilter == "Todas" { return list }
        return list.filter { $0.title == selectedActivityFilter }
    }

    private func formatHMS(_ mins: Int) -> String {
        String(format: "%d:%02d:00", mins / 60, mins % 60)
    }

    private func formatShortDate(_ iso: String) -> String {
        guard let d = store.isoFormatter.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    private func groupWorkoutsByMonth(_ items: [(iso: String, workout: EffortEventItem)]) -> [(monthTitle: String, items: [EffortEventItem])] {
        let mFmt = DateFormatter()
        mFmt.locale = Locale(identifier: "es_ES")
        mFmt.dateFormat = "MMMM 'de' yyyy"

        let ordered = sortNewestFirst
            ? items.sorted { ($0.iso, $0.workout.timeRange) > ($1.iso, $1.workout.timeRange) }
            : items.sorted { ($0.iso, $0.workout.timeRange) < ($1.iso, $1.workout.timeRange) }

        var groups: [(String, [EffortEventItem])] = []
        for entry in ordered {
            let key: String = {
                if let d = store.isoFormatter.date(from: entry.iso) {
                    return mFmt.string(from: d).lowercased()
                }
                return entry.iso
            }()
            if let last = groups.last, last.0 == key {
                groups[groups.count - 1].1.append(entry.workout)
            } else {
                groups.append((key, [entry.workout]))
            }
        }
        return groups
    }

    var body: some View {
        Group {
            switch currentRoute {
            case .activitiesDuration, .activitiesEnergy:
                activitiesOverviewView
            case .vo2Max:
                vo2MaxDetailView
            case .hrRecovery:
                hrRecoveryDetailView
            case .cardioFocus:
                cardioFocusDetailView
            case .hrZones:
                hrZonesDetailView
            case .strengthSets, .strengthVolume:
                strengthOverviewView
            case .muscleGroups:
                muscleGroupsDetailView
            }
        }
        .onAppear {
            currentRoute = route
            if route == .activitiesEnergy { selectedActivityKpi = 3 }
            else if route == .activitiesDuration { selectedActivityKpi = 0 }
            else if route == .strengthVolume { selectedStrengthKpi = 1 }
            else if route == .strengthSets { selectedStrengthKpi = 0 }
        }
    }

    // MARK: - 3A. Todas las actividades (Screenshots 7-11!)

    private var activitiesOverviewView: some View {
        let win = windowDates
        let curWorkoutsDated: [(iso: String, workout: EffortEventItem)] = win.isos.flatMap { iso in
            filterWorkouts(store.activeHistory[iso]?.workouts ?? []).map { (iso, $0) }
        }
        let prevWorkoutsDated: [(iso: String, workout: EffortEventItem)] = win.prevIsos.flatMap { iso in
            filterWorkouts(store.activeHistory[iso]?.workouts ?? []).map { (iso, $0) }
        }

        let curDur = curWorkoutsDated.reduce(0) { $0 + $1.workout.durationMin }
        let prevDur = prevWorkoutsDated.reduce(0) { $0 + $1.workout.durationMin }
        let curDist = curWorkoutsDated.compactMap(\.workout.distanceKm).reduce(0, +)
        let prevDist = prevWorkoutsDated.compactMap(\.workout.distanceKm).reduce(0, +)
        let curElev = win.isos.compactMap { store.activeHistory[$0]?.elevationM }.reduce(0, +)
            + curWorkoutsDated.compactMap(\.workout.elevationM).reduce(0, +)
        let prevElev = win.prevIsos.compactMap { store.activeHistory[$0]?.elevationM }.reduce(0, +)
            + prevWorkoutsDated.compactMap(\.workout.elevationM).reduce(0, +)
        let curKcal = curWorkoutsDated.reduce(0) { $0 + $1.workout.kcal }
        let prevKcal = prevWorkoutsDated.reduce(0) { $0 + $1.workout.kcal }

        // Pace & Speed from workouts with real distanceKm > 0
        let distWorkouts = curWorkoutsDated.filter { ($0.workout.distanceKm ?? 0) > 0.05 }
        let distKmSum = distWorkouts.compactMap(\.workout.distanceKm).reduce(0, +)
        let distMinSum = Double(distWorkouts.reduce(0) { $0 + $1.workout.durationMin })
        let paceMinPerKm: Double? = distKmSum > 0.1 ? (distMinSum / distKmSum) : nil
        let speedKmh: Double? = distMinSum > 0.5 && distKmSum > 0.1 ? (distKmSum / (distMinSum / 60.0)) : nil

        let hrVals = curWorkoutsDated.map(\.workout.avgHrBpm).filter { $0 > 0 }
        let avgWorkoutHr: Int? = hrVals.isEmpty ? nil : Int((Double(hrVals.reduce(0, +)) / Double(hrVals.count)).rounded())
        let powerVals = curWorkoutsDated.compactMap(\.workout.avgPowerW) + win.isos.compactMap { store.activeHistory[$0]?.avgPowerW }
        let avgPower: Double? = powerVals.isEmpty ? nil : (powerVals.reduce(0, +) / Double(powerVals.count))
        let cadVals = curWorkoutsDated.compactMap(\.workout.avgCadenceRpm) + win.isos.compactMap { store.activeHistory[$0]?.avgCadenceRpm }
        let avgCadence: Double? = cadVals.isEmpty ? nil : (cadVals.reduce(0, +) / Double(cadVals.count))

        // Daily series for ALL 9 KPI cards (0: Duración, 1: Distancia, 2: Elevación, 3: Calorías, 4: Ritmo, 5: Velocidad, 6: FC media, 7: Potencia, 8: Cadencia)
        func kpiDayValue(iso: String) -> Double {
            let ws = filterWorkouts(store.activeHistory[iso]?.workouts ?? [])
            switch selectedActivityKpi {
            case 0:
                return Double(ws.reduce(0) { $0 + $1.durationMin }) / 60.0
            case 1:
                return ws.compactMap(\.distanceKm).reduce(0, +)
            case 2:
                return (store.activeHistory[iso]?.elevationM ?? 0) + ws.compactMap(\.elevationM).reduce(0, +)
            case 3:
                return Double(ws.reduce(0) { $0 + $1.kcal })
            case 4:
                let dWs = ws.filter { ($0.distanceKm ?? 0) > 0.05 }
                let km = dWs.compactMap(\.distanceKm).reduce(0, +)
                let mins = Double(dWs.reduce(0) { $0 + $1.durationMin })
                return km > 0.05 ? (mins / km) : 0
            case 5:
                let dWs = ws.filter { ($0.distanceKm ?? 0) > 0.05 }
                let km = dWs.compactMap(\.distanceKm).reduce(0, +)
                let hrs = Double(dWs.reduce(0) { $0 + $1.durationMin }) / 60.0
                return hrs > 0.01 && km > 0.05 ? (km / hrs) : 0
            case 6:
                let hs = ws.map(\.avgHrBpm).filter { $0 > 0 }
                return hs.isEmpty ? 0 : Double(hs.reduce(0, +)) / Double(hs.count)
            case 7:
                let ps = ws.compactMap(\.avgPowerW) + (store.activeHistory[iso]?.avgPowerW.map { [$0] } ?? [])
                return ps.isEmpty ? 0 : (ps.reduce(0, +) / Double(ps.count))
            case 8:
                let cs = ws.compactMap(\.avgCadenceRpm) + (store.activeHistory[iso]?.avgCadenceRpm.map { [$0] } ?? [])
                return cs.isEmpty ? 0 : (cs.reduce(0, +) / Double(cs.count))
            default:
                return Double(ws.reduce(0) { $0 + $1.durationMin }) / 60.0
            }
        }
        let dailyCur: [Double] = win.isos.map { kpiDayValue(iso: $0) }
        let dailyPrev: [Double] = win.prevIsos.map { kpiDayValue(iso: $0) }

        let chartFormatter: (Double) -> String = { v in
            switch selectedActivityKpi {
            case 0: return String(format: "%.1fh", locale: Locale(identifier: "es_ES"), v)
            case 1: return String(format: "%.1f km", locale: Locale(identifier: "es_ES"), v)
            case 2: return "\(Int(v.rounded())) m"
            case 3: return "\(Int(v.rounded())) kcal"
            case 4:
                let totalSec = max(Int((v * 60.0).rounded()), 0)
                return String(format: "%d:%02d/km", totalSec / 60, totalSec % 60)
            case 5: return String(format: "%.1f km/h", locale: Locale(identifier: "es_ES"), v)
            case 6: return "\(Int(v.rounded())) ppm"
            case 7: return "\(Int(v.rounded())) W"
            case 8: return "\(Int(v.rounded())) rpm"
            default: return String(format: "%.1fh", locale: Locale(identifier: "es_ES"), v)
            }
        }

        let durDelta = curDur - prevDur
        let distDelta = curDist - prevDist
        let elevDelta = curElev - prevElev
        let kcalDelta = curKcal - prevKcal

        let groupedHistory = groupWorkoutsByMonth(curWorkoutsDated)

        let aiInsight: MetricFloatingAiInsight = {
            if curWorkoutsDated.isEmpty {
                return MetricFloatingAiInsight(
                    shortPillText: "Sin actividades en este período",
                    expandedHeadline: "Sin actividades registradas",
                    shortExpandedMessage: "No constan entrenamientos en estos \(spanDays) días. Sincroniza tu Atajo de Apple Health para importar tus sesiones.",
                    expandedMessage: "No constan entrenamientos en estos \(spanDays) días. Sincroniza tu Atajo de Apple Health para importar tus sesiones.",
                    structureIndex: 0, variationSeed: 1
                )
            }
            let moreActive = durDelta >= 0
            let head = moreActive ? "Un periodo más activo" : "Menor volumen de actividad"
            let dAbs = abs(durDelta)
            let msg = "En tus actividades, el cambio más destacado fue \(moreActive ? "sumar" : "reducir") \(dAbs / 60) h \(dAbs % 60) min frente al periodo anterior. El total acumulado llegó a \(curDur / 60) h \(curDur % 60) min y \(curKcal) kcal en estos \(spanDays) días."
            return MetricFloatingAiInsight(
                shortPillText: head,
                expandedHeadline: head,
                shortExpandedMessage: msg,
                expandedMessage: msg,
                structureIndex: 0, variationSeed: 2
            )
        }()

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Menu {
                                Button("Ordenar más recientes") { sortNewestFirst = true }
                                Button("Ordenar más antiguos") { sortNewestFirst = false }
                                Button(isBarMode ? "Ver línea acumulada" : "Ver barras diarias") { isBarMode.toggle() }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Menu {
                                    ForEach(availableActivityNames, id: \.self) { name in
                                        Button(name == "Todas" ? "Todas las actividades" : name) {
                                            selectedActivityFilter = name
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedActivityFilter == "Todas" ? "Todas las actividades" : selectedActivityFilter)
                                            .font(ImprovingFont.displayLarge(23))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                }

                                Text(win.rangeTitle)
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("Período actual vs. anterior")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Spacer()

                            // Bar vs Cumulative Line Toggle (Exact Match to Screenshot 7!)
                            HStack(spacing: 2) {
                                Button { isBarMode = true } label: {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(isBarMode ? BevelColors.textPrimary : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(isBarMode ? BevelColors.cardSubtle : .clear))
                                }
                                Button { isBarMode = false } label: {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 13))
                                        .foregroundColor(!isBarMode ? BevelColors.textPrimary : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(!isBarMode ? BevelColors.cardSubtle : .clear))
                                }
                            }
                            .padding(3)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                        }
                        .padding(.horizontal, 16)

                        // Horizontally Scrollable Selectable 9 KPI Cards (Exact Match to Screenshots 7, 8, 9!)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                activityKpiCard(
                                    idx: 0, title: "Duración de la act.",
                                    value: curDur > 0 ? formatHMS(curDur) : "No hay datos",
                                    deltaText: curDur > 0 ? formatHMS(abs(durDelta)) : nil,
                                    isUp: durDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 1, title: "Distancia",
                                    value: curDist > 0 ? String(format: "%.2f km", locale: Locale(identifier: "es_ES"), curDist) : "No hay datos",
                                    deltaText: curDist > 0 ? String(format: "%.2f km", locale: Locale(identifier: "es_ES"), abs(distDelta)) : nil,
                                    isUp: distDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 2, title: "Desnivel",
                                    value: curElev > 0 ? "\(Int(curElev.rounded())) m" : "No hay datos",
                                    deltaText: curElev > 0 ? "\(Int(abs(elevDelta).rounded())) m" : nil,
                                    isUp: elevDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 3, title: "Energía en actividad",
                                    value: curKcal > 0 ? "\(curKcal) kcal" : "No hay datos",
                                    deltaText: curKcal > 0 ? "\(abs(kcalDelta)) kcal" : nil,
                                    isUp: kcalDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 4, title: "Ritmo",
                                    value: paceMinPerKm.map { p in
                                        let m = Int(p)
                                        let s = Int(((p - Double(m)) * 60.0).rounded())
                                        return String(format: "%d:%02d /km", m, min(s, 59))
                                    } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 5, title: "Velocidad",
                                    value: speedKmh.map { String(format: "%.1f km/h", locale: Locale(identifier: "es_ES"), $0) } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 6, title: "Frecuencia cardíaca",
                                    value: avgWorkoutHr.map { "\($0) ppm" } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 7, title: "Potencia",
                                    value: avgPower.map { "\(Int($0.rounded())) W" } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 8, title: "Cadencia",
                                    value: avgCadence.map { "\(Int($0.rounded())) rpm" } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                            }
                            .padding(.horizontal, 16)
                        }

                        ActivityComparisonBarOrLineChart(
                            dailyCurrent: dailyCur,
                            dailyPrevious: dailyPrev,
                            dateLabels: win.shortLabels,
                            isBarMode: isBarMode,
                            accentStart: Color(hex: 0x3AC4E8),
                            accentEnd: BevelColors.cyanBright,
                            valueFormatter: chartFormatter
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)

                        Text(isBarMode ? "Total diario en el período seleccionado." : "Total acumulado en el período seleccionado, por días.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 14)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    // Monthly Grouped Sortable Activity History (Screenshots 10-11!)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Historial de actividad")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                sortNewestFirst.toggle()
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        if groupedHistory.isEmpty {
                            BevelCard(cornerRadius: 18) {
                                Text("No hay entrenamientos registrados en este período. Sincroniza Apple Health con el Atajo o registra tu próxima sesión.")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                        } else {
                            ForEach(groupedHistory, id: \.monthTitle) { group in
                                Text(group.monthTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(.top, 4)

                                ForEach(group.items) { w in
                                    Button {
                                        onOpenWorkout?(w)
                                    } label: {
                                        FitnessActivityHistoryRow(workout: w)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "act_\(selectedActivityFilter)_\(selectedRange)_\(selectedActivityKpi)",
                metricTitle: "Actividades",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "🚴"
            )
        }
    }

    private func activityKpiCard(idx: Int, title: String, value: String, deltaText: String?, isUp: Bool) -> some View {
        let active = selectedActivityKpi == idx
        let isNoData = value == "No hay datos"
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedActivityKpi = idx
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(ImprovingFont.metricTile(isNoData ? 17 : 20))
                    .monospacedDigit()
                    .foregroundColor(isNoData ? BevelColors.textMuted : BevelColors.textPrimary)
                    .lineLimit(1)
                if let d = deltaText {
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(BevelColors.skyBlue)
                        Text(d)
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundColor(BevelColors.skyBlue)
                    }
                } else {
                    Text("—")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textMuted)
                }
            }
            .frame(width: 146, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BevelColors.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(active ? Color.white.opacity(0.42) : BevelColors.cardBorder, lineWidth: active ? 1.3 : 0.8)
            )
        }
    }

    // MARK: - 3B. VO₂ máx. Detail Sheet (Exact Match to Screenshots 13-15!)

    private var vo2MaxDetailView: some View {
        let win = windowDates
        let values: [Double?] = win.isos.map { store.activeHistory[$0]?.vo2MaxMlKgMin }
        let rec = store.latestVo2MaxRecord
        let eval = rec.map { WhoopPhysiologyEngine.standardizeVo2Max($0.value, profile: store.userProfile) }
        let trendRows = WhoopPhysiologyEngine.computeMultiPeriodTrendRows(
            history: store.activeHistory,
            anchorDate: store.selectedDate
        ) { $0.vo2MaxMlKgMin }

        let d90 = trendRows.last?.delta
        let aiInsight: MetricFloatingAiInsight = {
            guard let r = rec, let e = eval else {
                return MetricFloatingAiInsight(
                    shortPillText: "Sin lecturas de VO₂ máx.",
                    expandedHeadline: "VO₂ máx. pendiente",
                    shortExpandedMessage: "Realiza caminatas o carreras al aire libre con Apple Watch y sincroniza con el Atajo para registrar tu VO₂ máx.",
                    expandedMessage: "Realiza caminatas o carreras al aire libre con Apple Watch y sincroniza con el Atajo para registrar tu VO₂ máx.",
                    structureIndex: 0, variationSeed: 1
                )
            }
            let head = (d90 ?? 0) > 0.3 ? "VO₂ máx: mejora gradual" : "VO₂ máx: banda \(e.categoryTitle)"
            let deltaSentence = d90.map { String(format: "Varió %+.1f mL/kg·min en los últimos 90 días.", locale: Locale(identifier: "es_ES"), $0) } ?? ""
            let msg = "Tu VO₂ máx. está en \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), r.value)) dentro de la banda \(e.categoryTitle) (\(e.cohortSubtitle)). \(deltaSentence)"
            return MetricFloatingAiInsight(shortPillText: head, expandedHeadline: head, shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 0, variationSeed: 3)
        }()

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "VO₂ máx.", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0.value) } ?? "Sin datos")
                                    .font(ImprovingFont.displayLarge(rec != nil ? 36 : 26))
                                    .monospacedDigit()
                                    .foregroundColor(rec != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if let e = eval {
                                Text(e.categoryTitle)
                                    .font(ImprovingFont.sectionTitle(18))
                                    .foregroundColor(e.activeColor)
                            }
                        }
                        .padding(.horizontal, 16)

                        Vo2AmberAreaChart(
                            optionalPoints: values,
                            dates: win.shortLabels,
                            lineStartColor: BevelColors.amberStart,
                            lineEndColor: BevelColors.orangeEnd,
                            valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        if let e = eval, let r = rec {
                            FiveSegmentRangeBar(
                                labels: e.labels,
                                activeSegmentIndex: e.activeSegmentIndex,
                                activeColor: e.activeColor,
                                pointerFraction: e.pointerFraction,
                                rangeTitle: e.categoryTitle,
                                subtitle: e.cohortSubtitle,
                                footerDate: "Último dato el \(formatShortDate(r.dateIso))"
                            )
                        }

                        // Análisis de tendencias (3d / 7d / 14d / 30d / 90d — Exact Match to Screenshot 14!)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Análisis de tendencias")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            if let r = rec {
                                Text("Último dato el \(formatShortDate(r.dateIso))")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Período").frame(width: 90, alignment: .leading)
                                    Text("Variación").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Tendencia").frame(width: 78, alignment: .trailing)
                                }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                ForEach(Array(trendRows.enumerated()), id: \.element.id) { idx, row in
                                    if idx > 0 { Divider().background(BevelColors.divider).padding(.horizontal, 14) }
                                    let isStrong = abs(row.delta ?? 0) >= 1.5
                                    let arrowIcon: String = {
                                        guard let d = row.delta else { return "minus.circle.fill" }
                                        if d >= 1.0 { return "arrow.up.circle.fill" }
                                        if d <= -1.0 { return "arrow.down.circle.fill" }
                                        return "arrow.right.circle.fill"
                                    }()
                                    let badgeColor: Color = {
                                        guard let d = row.delta else { return BevelColors.textMuted }
                                        if d >= 1.0 { return BevelColors.skyBlue }
                                        if d <= -1.0 { return BevelColors.coralHigh }
                                        return BevelColors.textMuted
                                    }()
                                    HStack {
                                        Text(row.label)
                                            .font(ImprovingFont.body(14.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .frame(width: 90, alignment: .leading)

                                        HStack(spacing: 6) {
                                            Image(systemName: arrowIcon)
                                                .font(.system(size: 14))
                                                .foregroundColor(badgeColor)
                                            Text(row.delta.map { String(format: "%+.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "—")
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .monospacedDigit()
                                                .foregroundColor(BevelColors.textPrimary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if row.sparklinePoints.count >= 2 {
                                            TrendSparklineWithBand(
                                                points: row.sparklinePoints,
                                                lineColor: isStrong ? BevelColors.skyBlue : Color(hex: 0x8E939E),
                                                fillUnder: true,
                                                showBand: false,
                                                showGlowDot: false
                                            )
                                            .frame(width: 78, height: 24)
                                        } else {
                                            Text("—").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted).frame(width: 78, alignment: .trailing)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                            }
                        }

                        Text("Basado en las medias móviles de 7 días durante el período seleccionado.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)

                        // Educational card (Screenshot 15!)
                        Text("¿Qué es el VO₂ máx.?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("El VO₂ máx. mide el volumen máximo de oxígeno que tu cuerpo puede usar durante un ejercicio intenso. Es un indicador clave de la forma física cardiovascular y la resistencia.")
                                Text("Mejorar tu VO₂ máx. puede potenciar tu rendimiento deportivo, aumentar tus niveles de energía y favorecer la salud cardíaca. Unos niveles más altos de VO₂ máx. están relacionados con una mejor forma física general y una mayor longevidad.")
                            }
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(3.5)
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_vo2",
                                badgeIcon: "lungs.fill",
                                heroTitle: "VO₂ máx.",
                                heroSubtitle: "Fundamentos",
                                cardTitle: "Fundamentos: VO₂ máx.",
                                cardDescription: "Entiende cómo refleja tu VO₂ máx. tu forma física y longevidad.",
                                gradientHexA: 0x3D495C,
                                gradientHexB: 0x57483D,
                                fullGuideBody: "Combinar un 80% de sesiones aeróbicas suaves en Zona 2 con un 20% de intervalos de alta intensidad en Zonas 4–5 es la estrategia con mayor respaldo científico para elevar tu VO₂ máx. de forma constante."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "vo2_\(selectedRange)_\(windowPageOffset)",
                metricTitle: "VO₂ máx.",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "📈"
            )
        }
    }

    // MARK: - 3C. Recuperación de FC (HRR) Detail Sheet (Exact Match to Screenshots 16-18!)

    private var hrRecoveryDetailView: some View {
        let win = windowDates
        let values: [Double?] = win.isos.map { iso in
            guard let day = store.activeHistory[iso] else { return nil }
            if selectedActivityFilter == "Todas" {
                return day.hrRecoveryBpm
            }
            let matching = day.workouts.filter { $0.title == selectedActivityFilter }.compactMap(\.hrRecovery1MinBpm)
            if !matching.isEmpty {
                return matching.reduce(0, +) / Double(matching.count)
            }
            return day.workouts.contains(where: { $0.title == selectedActivityFilter }) ? day.hrRecoveryBpm : nil
        }
        let realVals = values.compactMap { $0 }
        let avgHrr = realVals.isEmpty ? nil : Int((realVals.reduce(0, +) / Double(realVals.count)).rounded())
        let rec = store.latestHrRecoveryRecord
        let eval = rec.map { WhoopPhysiologyEngine.standardizeHrRecovery($0.value, profile: store.userProfile) }

        let aiInsight: MetricFloatingAiInsight = {
            guard let r = rec, let e = eval else {
                return MetricFloatingAiInsight(
                    shortPillText: "Sin lecturas de HRR",
                    expandedHeadline: "Recuperación de FC",
                    shortExpandedMessage: "Tras tus sesiones con Apple Watch, Improving lee o calcula automáticamente cuántos ppm baja tu pulso en el primer minuto.",
                    expandedMessage: "Tras tus sesiones con Apple Watch, Improving lee o calcula automáticamente cuántos ppm baja tu pulso en el primer minuto.",
                    structureIndex: 0, variationSeed: 1
                )
            }
            let pill = (avgHrr ?? Int(r.value)) >= 30 ? "Buen promedio del periodo" : "HRR en rango \(e.categoryTitle)"
            let msg = "Tu última recuperación de frecuencia cardíaca fue de \(Int(r.value.rounded())) ppm (\(e.categoryTitle))." + (avgHrr.map { " El promedio del periodo seleccionado se sitúa en \($0) ppm." } ?? "")
            return MetricFloatingAiInsight(shortPillText: pill, expandedHeadline: pill, shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 0, variationSeed: 4)
        }()

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Recuperación de frecuencia cardíaca", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.map { "\(Int($0.value.rounded())) ppm" } ?? "Sin datos")
                                    .font(ImprovingFont.displayLarge(rec != nil ? 36 : 26))
                                    .monospacedDigit()
                                    .foregroundColor(rec != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if let e = eval {
                                Text(e.categoryTitle)
                                    .font(ImprovingFont.sectionTitle(18))
                                    .foregroundColor(e.activeColor)
                            }
                        }
                        .padding(.horizontal, 16)

                        activityFilterChipsBar

                        Vo2AmberAreaChart(
                            optionalPoints: values,
                            dates: win.shortLabels,
                            lineStartColor: BevelColors.strengthPink,
                            lineEndColor: BevelColors.amberStart,
                            averageBadgeText: avgHrr.map { "Prom. \($0) ppm" },
                            valueFormatter: { "\(Int($0.rounded())) ppm" }
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        if let e = eval, let r = rec {
                            FiveSegmentRangeBar(
                                labels: e.labels,
                                activeSegmentIndex: e.activeSegmentIndex,
                                activeColor: e.activeColor,
                                pointerFraction: e.pointerFraction,
                                rangeTitle: e.categoryTitle,
                                subtitle: e.cohortSubtitle,
                                footerDate: "Último dato el \(formatShortDate(r.dateIso))"
                            )
                        }

                        Text("¿Qué es la recuperación de la frecuencia cardíaca?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("La recuperación de la frecuencia cardíaca (HRR) mide la rapidez con la que tu frecuencia cardíaca vuelve a los valores normales después de hacer ejercicio, lo que indica tu estado cardiovascular y tu capacidad de recuperación.")
                                Text("Una HRR más rápida es señal de buena salud cardíaca, mientras que una recuperación más lenta puede indicar fatiga o la necesidad de mejorar tu capacidad aeróbica. Puedes mejorar la HRR con entrenamiento aeróbico, hidratación, sueño y control del estrés.")
                            }
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(3.5)
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_hrr",
                                badgeIcon: "heart.circle.fill",
                                heroTitle: "Recuperación FC",
                                heroSubtitle: "Fundamentos",
                                cardTitle: "Fundamentos: Recuperación de FC",
                                cardDescription: "Entiende cómo se recupera tu corazón tras esfuerzos exigentes.",
                                gradientHexA: 0x3D4C3E,
                                gradientHexB: 0x5A483A,
                                fullGuideBody: "La caída de pulsaciones en el primer minuto tras detener un entrenamiento refleja la reactivación parasimpática del nervio vago. Valores por encima de 30–35 ppm indican una excelente respuesta autónoma."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "hrr_\(selectedActivityFilter)_\(selectedRange)",
                metricTitle: "HRR",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "📈"
            )
        }
    }

    // MARK: - 3D. Foco cardiovascular Detail Sheet (Exact Match to Screenshots 19-21!)

    private var cardioFocusDetailView: some View {
        let win = windowDates
        let dailyTriples: [(low: Int, high: Int, anaero: Int)] = win.isos.map { iso in
            guard let day = store.activeHistory[iso] else { return (0, 0, 0) }
            if selectedActivityFilter != "Todas" {
                let ws = day.workouts.filter { $0.title == selectedActivityFilter }
                let z6 = ws.reduce([0, 0, 0, 0, 0, 0]) { acc, w in
                    let arr = w.hrZoneMinutes6 ?? [0, 0, 0, 0, 0, 0]
                    return (0..<6).map { acc[$0] + ($0 < arr.count ? arr[$0] : 0) }
                }
                return (z6[0] + z6[1] + z6[2], z6[3] + z6[4], z6[5])
            }
            let z0 = day.hrZone0Minutes ?? 0
            let z = day.hrZoneMinutes
            let low = z0 + (z.count > 0 ? z[0] : 0) + (z.count > 1 ? z[1] : 0)
            let high = (z.count > 2 ? z[2] : 0) + (z.count > 3 ? z[3] : 0)
            let an = z.count > 4 ? z[4] : 0
            return (low, high, an)
        }
        let totLow = dailyTriples.reduce(0) { $0 + $1.low }
        let totHigh = dailyTriples.reduce(0) { $0 + $1.high }
        let totAn = dailyTriples.reduce(0) { $0 + $1.anaero }
        let grandTotal = totLow + totHigh + totAn
        let pLow = grandTotal > 0 ? Int((Double(totLow) / Double(grandTotal) * 100.0).rounded()) : 0
        let pHigh = grandTotal > 0 ? Int((Double(totHigh) / Double(grandTotal) * 100.0).rounded()) : 0
        let pAn = grandTotal > 0 ? max(0, 100 - pLow - pHigh) : 0

        let domTitle = grandTotal == 0 ? "Sin datos" : (pLow >= pHigh && pLow >= pAn ? "Aeróbico bajo" : (pHigh >= pAn ? "Aeróbico alto" : "Anaeróbico"))
        let domPct = max(pLow, max(pHigh, pAn))

        let aiInsight = MetricFloatingAiInsight(
            shortPillText: grandTotal == 0 ? "Sin zonas registradas" : (pLow >= 70 ? "Predomina el trabajo suave" : "Buen estímulo intenso"),
            expandedHeadline: grandTotal == 0 ? "Foco cardiovascular" : (pLow >= 70 ? "Predomina el trabajo suave" : "Foco equilibrado"),
            shortExpandedMessage: grandTotal == 0
                ? "Todavía no hay minutos en zonas cardíacas en este período."
                : "Un \(pLow)% de tu volumen fue aeróbico bajo (\(totLow) min), \(pHigh)% aeróbico alto (\(totHigh) min) y \(pAn)% anaeróbico (\(totAn) min).",
            expandedMessage: grandTotal == 0
                ? "Todavía no hay minutos en zonas cardíacas en este período."
                : "Un \(pLow)% de tu volumen fue aeróbico bajo (\(totLow) min), \(pHigh)% aeróbico alto (\(totHigh) min) y \(pAn)% anaeróbico (\(totAn) min). Añadir 1 bloque semanal en Zona 4 ayuda a impulsar tu VO₂ máx.",
            structureIndex: 0, variationSeed: 5
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Foco cardiovascular", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(domTitle)
                                    .font(ImprovingFont.displayLarge(26))
                                    .foregroundColor(grandTotal > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if grandTotal > 0 {
                                Text("\(domPct) %")
                                    .font(ImprovingFont.sectionTitle(18))
                                    .monospacedDigit()
                                    .foregroundColor(Color(hex: 0x62E2E8))
                            }
                        }
                        .padding(.horizontal, 16)

                        activityFilterChipsBar

                        CardioFocusStackedBarChart(dailyTriples: dailyTriples, dateLabels: win.shortLabels)
                            .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Desglose del foco cardiovascular")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Estado").frame(width: 96, alignment: .leading)
                                    Text("Valor").frame(width: 44, alignment: .leading)
                                    Spacer()
                                    Text("%").frame(width: 44, alignment: .trailing)
                                }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                focusRow("Aeró. bajo", val: "\(totLow)", pct: pLow, color: Color(hex: 0x62E2E8))
                                Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                focusRow("Aeró. alto", val: "\(totHigh)", pct: pHigh, color: Color(hex: 0x5682FF))
                                Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                focusRow("Anaeróbico", val: "\(totAn)", pct: pAn, color: Color(hex: 0xA855F7))
                            }
                        }

                        Text("¿Qué es el foco cardiovascular?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("El foco cardiovascular muestra la división en zonas aeróbicas durante tus ejercicios. Improving utiliza tu VO₂ máx. e intensidad de entrenamiento para estimar tus umbrales que se acumulan con el tiempo:")
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textSecondary)

                                zoneExplainBullet(color: Color(hex: 0x62E2E8), title: "Aeróbico bajo:", body: "esfuerzos de baja intensidad pero prolongados que se suelen realizar a un ritmo de conversación.")
                                zoneExplainBullet(color: Color(hex: 0x5682FF), title: "Aeróbico alto:", body: "esfuerzos con una intensidad de moderadamente alta a alta, donde tu frecuencia cardíaca se mantiene muy elevada durante un periodo prolongado.")
                                zoneExplainBullet(color: Color(hex: 0xA855F7), title: "Anaeróbico:", body: "esfuerzos de corta duración y alta intensidad que elevan rápidamente tu frecuencia cardíaca, como entrenamiento por intervalos o HIIT.")
                            }
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_cf",
                                badgeIcon: "square.stack.3d.up.fill",
                                heroTitle: "Enfoque cardio",
                                heroSubtitle: "Fundamentos",
                                cardTitle: "Fundamentos: Enfoque cardio",
                                cardDescription: "Optimiza tu intensidad de entrenamiento con un esfuerzo aeróbico equilibrado.",
                                gradientHexA: 0x4C5968,
                                gradientHexB: 0x665850,
                                fullGuideBody: "La regla 80/20 en entrenamiento de resistencia consiste en acumular alrededor de un 80% del tiempo en aeróbico bajo para construir mitocondrias y capilares, reservando el 20% para bloques intensos."
                            ),
                            FitnessResourceItem(
                                id: "res_hrz_cf",
                                badgeIcon: "waveform.path.ecg",
                                heroTitle: "Zonas de FC",
                                heroSubtitle: "Z0 – Z5",
                                cardTitle: "Zonas de frecuencia cardíaca",
                                cardDescription: "Entiende cada zona cardíaca y cuándo entrenar en cada umbral.",
                                gradientHexA: 0x5C3E2E,
                                gradientHexB: 0x262832,
                                fullGuideBody: "Tus 6 zonas se calculan automáticamente con la fórmula de Tanaka y Karvonen a partir de tu edad y tu FC en reposo real."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "cf_\(selectedActivityFilter)_\(selectedRange)",
                metricTitle: "Foco cardio",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "🚴"
            )
        }
    }

    // MARK: - 3E. Zonas de frecuencia cardíaca Detail Sheet (Exact Match to Screenshots 22-24!)

    private var hrZonesDetailView: some View {
        let win = windowDates
        let minutes6: [Int] = {
            var sums = [0, 0, 0, 0, 0, 0]
            for iso in win.isos {
                guard let day = store.activeHistory[iso] else { continue }
                if selectedActivityFilter != "Todas" {
                    for w in day.workouts where w.title == selectedActivityFilter {
                        if let z6 = w.hrZoneMinutes6 {
                            for i in 0..<min(6, z6.count) { sums[i] += z6[i] }
                        }
                    }
                } else {
                    sums[0] += day.hrZone0Minutes ?? 0
                    for i in 0..<min(5, day.hrZoneMinutes.count) {
                        sums[i + 1] += day.hrZoneMinutes[i]
                    }
                }
            }
            return sums
        }()
        let totalM = minutes6.reduce(0, +)
        let dominantIdx = minutes6.enumerated().max(by: { $0.element < $1.element })?.offset ?? 1
        let activeIdx = (selectedZoneIdx >= 0 && selectedZoneIdx < 6 && minutes6[selectedZoneIdx] > 0) ? selectedZoneIdx : dominantIdx
        let bpmRanges = WhoopPhysiologyEngine.hrZoneRangesBpm(profile: store.userProfile, restingHrBpm: store.restingHrBpm > 30 ? store.restingHrBpm : nil)
        let activeRange = bpmRanges[min(activeIdx, bpmRanges.count - 1)]
        let activeMins = minutes6[activeIdx]
        let activeDurText = activeMins >= 60 ? "\(activeMins / 60) h \(activeMins % 60) min" : "\(activeMins) min"

        let aiInsight = MetricFloatingAiInsight(
            shortPillText: totalM == 0 ? "Sin zonas registradas" : (dominantIdx <= 2 ? "Mucho movimiento suave" : "Buena carga cardiovascular"),
            expandedHeadline: "Zonas de frecuencia cardíaca",
            shortExpandedMessage: totalM == 0
                ? "Todavía no se acumularon minutos por zonas en este período."
                : "Tu zona predominante es Zona \(dominantIdx) con \(minutes6[dominantIdx]) min (\(bpmRanges[dominantIdx].low)–\(bpmRanges[dominantIdx].high) ppm).",
            expandedMessage: totalM == 0
                ? "Todavía no se acumularon minutos por zonas en este período."
                : "Tu zona predominante es Zona \(dominantIdx) con \(minutes6[dominantIdx]) min (\(bpmRanges[dominantIdx].low)–\(bpmRanges[dominantIdx].high) ppm). Total acumulado: \(totalM / 60) h \(totalM % 60) min.",
            structureIndex: 0, variationSeed: 6
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Zonas de frecuencia cardíaca", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(totalM > 0 ? "Zona \(activeIdx)" : "Sin datos")
                                    .font(ImprovingFont.displayLarge(28))
                                    .foregroundColor(totalM > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if totalM > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(activeDurText)
                                        .font(ImprovingFont.sectionTitle(17))
                                        .monospacedDigit()
                                        .foregroundColor(HrZonesSixBarChart.zoneColors[activeIdx])
                                    Text("\(activeRange.low)–\(activeRange.high) ppm")
                                        .font(ImprovingFont.caption(13))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        activityFilterChipsBar

                        HrZonesSixBarChart(minutes6: minutes6, selectedZone: $selectedZoneIdx)
                            .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("¿Qué son las zonas de frecuencia cardíaca?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Las zonas de frecuencia cardíaca son rangos que representan diferentes niveles de intensidad de ejercicio. Cada zona tiene una finalidad distinta, desde el descanso y la recuperación hasta el esfuerzo máximo.")
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textSecondary)

                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[0], title: "Zona 0 (\(bpmRanges[0].low)–\(bpmRanges[0].high) ppm):", body: "el histórico de tu frecuencia cardíaca, que representa el nivel más bajo de intensidad.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[1], title: "Zona 1 (\(bpmRanges[1].low)–\(bpmRanges[1].high) ppm):", body: "recuperación activa para el calentamiento y el enfriamiento. El esfuerzo se nota ligero y cómodo.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[2], title: "Zona 2 (\(bpmRanges[2].low)–\(bpmRanges[2].high) ppm):", body: "esfuerzo sostenido para entrenamientos más largos que desarrolla la resistencia y usa una mayor proporción de grasa como fuente de energía.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[3], title: "Zona 3 (\(bpmRanges[3].low)–\(bpmRanges[3].high) ppm):", body: "esfuerzo moderado que mejora la capacidad cardiovascular. La respiración es más profunda, pero controlada.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[4], title: "Zona 4 (\(bpmRanges[4].low)–\(bpmRanges[4].high) ppm):", body: "esfuerzo de alta intensidad para sprints e intervalos. La respiración es agitada y el esfuerzo solo se puede mantener durante poco tiempo.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[5], title: "Zona 5 (\(bpmRanges[5].low)–\(bpmRanges[5].high) ppm):", body: "esfuerzo máximo para ráfagas cortas e intensas. Este esfuerzo solo se puede mantener durante muy poco tiempo.")
                            }
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_hrz",
                                badgeIcon: "heart.text.square.fill",
                                heroTitle: "Zonas de FC",
                                heroSubtitle: "Z0 – Z5",
                                cardTitle: "Zonas de frecuencia cardíaca",
                                cardDescription: "Aprende a utilizar tus zonas de pulso para planificar cada sesión.",
                                gradientHexA: 0x5B3F30,
                                gradientHexB: 0x262832,
                                fullGuideBody: "Tus zonas se calibran automáticamente con tu FC máxima de Tanaka (208 − 0,7 × edad) y tu FC en reposo medida por el Apple Watch."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "hrz_\(selectedActivityFilter)_\(selectedRange)",
                metricTitle: "Zonas de FC",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "🚴"
            )
        }
    }

    // MARK: - 3F. Todos los músculos (Fuerza Overview — Exact Match to Screenshots 25-28!)

    private var strengthOverviewView: some View {
        let win = windowDates
        let setsCurByDay = Dictionary(grouping: store.strengthLogs.filter { s in
            guard s.completed else { return false }
            if selectedMuscleDropdown == "Todos los músculos" { return true }
            return s.primaryMuscles.contains(where: { $0.rawValue == selectedMuscleDropdown })
                || s.secondaryMuscles.contains(where: { $0.rawValue == selectedMuscleDropdown })
        }, by: \.dateIso)

        let dailySetsCur: [Double] = win.isos.map { iso in
            let logged = setsCurByDay[iso]?.count ?? 0
            let wkSets = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalSets).reduce(0, +)
            return Double(max(logged, wkSets))
        }
        let dailySetsPrev: [Double] = win.prevIsos.map { iso in
            let logged = setsCurByDay[iso]?.count ?? 0
            let wkSets = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalSets).reduce(0, +)
            return Double(max(logged, wkSets))
        }
        let dailyVolCur: [Double] = win.isos.map { iso in
            let logged = (setsCurByDay[iso] ?? []).reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
            let wkVol = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalVolumeKg).reduce(0, +)
            return max(logged, wkVol)
        }
        let dailyVolPrev: [Double] = win.prevIsos.map { iso in
            let logged = (setsCurByDay[iso] ?? []).reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
            let wkVol = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalVolumeKg).reduce(0, +)
            return max(logged, wkVol)
        }

        let totSetsCur = Int(dailySetsCur.reduce(0, +).rounded())
        let totSetsPrev = Int(dailySetsPrev.reduce(0, +).rounded())
        let totVolCur = Int(dailyVolCur.reduce(0, +).rounded())
        let totVolPrev = Int(dailyVolPrev.reduce(0, +).rounded())
        let muscAnalysis = store.trainingLoadAnalysis(tab: .muscular, spanDays: spanDays, windowPageOffset: windowPageOffset)

        let curWorkoutsDated: [(iso: String, workout: EffortEventItem)] = win.isos.flatMap { iso in
            (store.activeHistory[iso]?.workouts ?? []).map { (iso, $0) }
        }
        let groupedHistory = groupWorkoutsByMonth(curWorkoutsDated)

        let chartCur = selectedStrengthKpi == 1 ? dailyVolCur : (selectedStrengthKpi == 2 ? muscAnalysis.points.map(\.load) : dailySetsCur)
        let chartPrev = selectedStrengthKpi == 1 ? dailyVolPrev : (selectedStrengthKpi == 2 ? Array(repeating: 0.0, count: chartCur.count) : dailySetsPrev)
        let fmt: (Double) -> String = { v in
            if selectedStrengthKpi == 1 {
                return v >= 1000 ? String(format: "%.2fk", locale: Locale(identifier: "es_ES"), v / 1000.0) : "\(Int(v.rounded()))"
            }
            return "\(Int(v.rounded()))"
        }

        let aiInsight = MetricFloatingAiInsight(
            shortPillText: totSetsCur > 0 ? "Fuerza retomada" : "Sin series registradas",
            expandedHeadline: totSetsCur > 0 ? "Fuerza retomada" : "Registra tu fuerza",
            shortExpandedMessage: totSetsCur > 0
                ? "Has completado \(totSetsCur) series y \(totVolCur) kg acumulados en estos \(spanDays) días (carga muscular \(muscAnalysis.currentLoad))."
                : "Registra tus series en Fitness o inicia una rutina anclada para ver aquí el volumen total y la frescura por músculo.",
            expandedMessage: totSetsCur > 0
                ? "Has completado \(totSetsCur) series y \(totVolCur) kg acumulados en estos \(spanDays) días (carga muscular \(muscAnalysis.currentLoad), estado \(muscAnalysis.currentState.rawValue))."
                : "Registra tus series en Fitness o inicia una rutina anclada para ver aquí el volumen total y la frescura por músculo.",
            structureIndex: 0, variationSeed: 7
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Button {
                                currentRoute = .muscleGroups
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 12))
                                    Text("Mapa muscular").font(ImprovingFont.caption(12)).fontWeight(.semibold)
                                }
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule().fill(BevelColors.glassChromeFill))
                                .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Menu {
                                    Button("Todos los músculos") { selectedMuscleDropdown = "Todos los músculos" }
                                    ForEach(MuscleGroupKind.allCases) { m in
                                        Button(m.rawValue) { selectedMuscleDropdown = m.rawValue }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedMuscleDropdown)
                                            .font(ImprovingFont.displayLarge(23))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                }
                                Text(win.rangeTitle)
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("Período actual vs. anterior")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                Button { isBarMode = true } label: {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(isBarMode ? BevelColors.textPrimary : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(isBarMode ? BevelColors.cardSubtle : .clear))
                                }
                                Button { isBarMode = false } label: {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 13))
                                        .foregroundColor(!isBarMode ? BevelColors.textPrimary : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(!isBarMode ? BevelColors.cardSubtle : .clear))
                                }
                            }
                            .padding(3)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                strengthKpiCard(idx: 0, title: "Total series", value: "\(totSetsCur)", sub: "\(abs(totSetsCur - totSetsPrev))", isDelta: true, isUp: totSetsCur >= totSetsPrev)
                                strengthKpiCard(idx: 1, title: "Volumen total", value: "\(totVolCur) kg", sub: "\(abs(totVolCur - totVolPrev)) kg", isDelta: true, isUp: totVolCur >= totVolPrev)
                                strengthKpiCard(idx: 2, title: "Carga", value: "\(muscAnalysis.currentLoad)", sub: muscAnalysis.currentState.rawValue, isDelta: false, isUp: true)
                            }
                            .padding(.horizontal, 16)
                        }

                        ActivityComparisonBarOrLineChart(
                            dailyCurrent: chartCur,
                            dailyPrevious: chartPrev,
                            dateLabels: win.shortLabels,
                            isBarMode: isBarMode,
                            accentStart: Color(hex: 0xEE7A5A),
                            accentEnd: BevelColors.strengthPink,
                            valueFormatter: fmt
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)

                        Text("Total acumulado en el período seleccionado, por días.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 14)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Historial de actividad")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button { sortNewestFirst.toggle() } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        if groupedHistory.isEmpty {
                            BevelCard(cornerRadius: 18) {
                                Text("No hay actividades registradas en este período.")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(16)
                            }
                        } else {
                            ForEach(groupedHistory, id: \.monthTitle) { g in
                                Text(g.monthTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(.top, 4)
                                ForEach(g.items) { w in
                                    Button {
                                        onOpenWorkout?(w)
                                    } label: {
                                        FitnessActivityHistoryRow(workout: w)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "str_\(selectedStrengthKpi)_\(selectedRange)",
                metricTitle: "Fuerza",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "💪"
            )
        }
    }

    private func strengthKpiCard(idx: Int, title: String, value: String, sub: String, isDelta: Bool, isUp: Bool) -> some View {
        let active = selectedStrengthKpi == idx
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedStrengthKpi = idx
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary).lineLimit(1)
                Text(value).font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary).lineLimit(1)
                if isDelta {
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(BevelColors.skyBlue)
                        Text(sub).font(ImprovingFont.caption(12)).fontWeight(.semibold).monospacedDigit().foregroundColor(BevelColors.skyBlue)
                    }
                } else {
                    Text(sub).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                }
            }
            .frame(width: 146, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BevelColors.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(active ? Color.white.opacity(0.42) : BevelColors.cardBorder, lineWidth: active ? 1.3 : 0.8)
            )
        }
    }

    // MARK: - 3G. Grupos musculares (Exact Match to Screenshots 29-33!)

    private var muscleGroupsDetailView: some View {
        let cal = Calendar.current
        let targetDate = cal.date(byAdding: .day, value: -muscleDateOffset, to: store.selectedDate) ?? store.selectedDate
        let snapshots = store.muscleGroupSnapshots(for: targetDate)

        let dateBarText: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            if muscleDateOffset == 0 && store.dayOffset == 0 {
                f.dateFormat = "'Hoy,' d 'de' MMMM"
            } else {
                f.dateFormat = "EEE, d 'de' MMMM"
            }
            return f.string(from: targetDate).capitalized
        }()

        let filtered: [MuscleGroupSnapshot] = {
            var list = snapshots
            if let f = muscleStateFilter {
                list = list.filter { $0.state == f }
            }
            if selectedMuscleDropdown != "Todos los músculos" {
                list = list.filter { $0.muscle.rawValue == selectedMuscleDropdown }
            }
            let rank: (MuscleFreshnessState) -> Int = { st in
                switch st {
                case .recovered: return 0
                case .fatigued: return 1
                case .exhausted: return 2
                case .calibrating: return 3
                }
            }
            return list.sorted { a, b in
                if sortNewestFirst {
                    if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
                    return a.freshnessPct > b.freshnessPct
                } else {
                    return a.freshnessPct < b.freshnessPct
                }
            }
        }()

        let recCnt = snapshots.filter { $0.state == .recovered }.count
        let fatCnt = snapshots.filter { $0.state == .fatigued || $0.state == .exhausted }.count
        let aiInsight = MetricFloatingAiInsight(
            shortPillText: fatCnt > 0 ? "Músculos listos y otros aún fatigados" : (recCnt > 0 ? "Grupos musculares recuperados" : "Calibrando grupos musculares"),
            expandedHeadline: fatCnt > 0 ? "Músculos listos y otros aún fatigados" : "Estado muscular actual",
            shortExpandedMessage: fatCnt > 0
                ? "Tienes \(recCnt) grupos recuperados en verde y \(fatCnt) aún fatigados tras tus sesiones recientes. Prioriza los grupos frescos si entrenas hoy."
                : "Registra sesiones de fuerza o sincroniza tus entrenamientos de Apple Health para seguir la recuperación individual de los 20 grupos musculares.",
            expandedMessage: fatCnt > 0
                ? "Tienes \(recCnt) grupos recuperados en verde y \(fatCnt) aún fatigados tras tus sesiones recientes. Prioriza los grupos frescos si entrenas hoy y deja 48h a los fatigados."
                : "Registra sesiones de fuerza o sincroniza tus entrenamientos de Apple Health para seguir la recuperación individual de los 20 grupos musculares.",
            structureIndex: 0, variationSeed: 8
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Grupos musculares", onBack: onBack)

                        // Mode Tabs (Volumen total | Carga muscular | Frescura muscular)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                muscleModePill("Volumen total", idx: 0)
                                muscleModePill("Carga muscular", idx: 1)
                                muscleModePill("Frescura muscular", idx: 2)
                            }
                            .padding(.horizontal, 16)
                        }

                        // Dual Front & Back Anatomical Muscle Map (Screenshot 29!)
                        AnatomicalMuscleMapCanvas(
                            snapshots: snapshots,
                            filterState: muscleStateFilter,
                            compact: false
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)

                        // Filter Chips (Todo | • Recuperado | • Fatigado | • Agotado)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                muscleFilterChip(title: "Todo", dotColor: nil, active: muscleStateFilter == nil) {
                                    muscleStateFilter = nil
                                }
                                muscleFilterChip(title: "Recuperado", dotColor: BevelColors.greenPrimary, active: muscleStateFilter == .recovered) {
                                    muscleStateFilter = .recovered
                                }
                                muscleFilterChip(title: "Fatigado", dotColor: BevelColors.amberStart, active: muscleStateFilter == .fatigued) {
                                    muscleStateFilter = .fatigued
                                }
                                muscleFilterChip(title: "Agotado", dotColor: BevelColors.coralHigh, active: muscleStateFilter == .exhausted) {
                                    muscleStateFilter = .exhausted
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Date Stepper Bar (<  Hoy, 23 de noviembre  📅  >)
                        HStack(spacing: 8) {
                            Button { muscleDateOffset += 1 } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            Text(dateBarText)
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                            Button { muscleDateOffset = 0 } label: {
                                Image(systemName: "calendar")
                                    .font(.system(size: 13))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            Button { muscleDateOffset = max(0, muscleDateOffset - 1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(muscleDateOffset > 0 ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            .disabled(muscleDateOffset == 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    // 20-Muscle List (Screenshots 30-33!)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Menu {
                                Button("Todos los músculos") { selectedMuscleDropdown = "Todos los músculos" }
                                ForEach(MuscleGroupKind.allCases) { m in
                                    Button(m.rawValue) { selectedMuscleDropdown = m.rawValue }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(selectedMuscleDropdown)
                                        .font(ImprovingFont.cardTitle(15.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            Spacer()
                            Button { sortNewestFirst.toggle() } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        ForEach(filtered) { snap in
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 13) {
                                    MuscleMiniThumbnailView(muscle: snap.muscle, color: snap.state.color)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(snap.muscle.rawValue)
                                            .font(ImprovingFont.cardTitle(15))
                                            .foregroundColor(BevelColors.textPrimary)
                                        if muscleModeTab == 0 {
                                            Text("\(snap.recentSets) series · \(Int(snap.recentVolumeKg.rounded())) kg")
                                                .font(ImprovingFont.caption(13))
                                                .foregroundColor(BevelColors.textSecondary)
                                        } else if muscleModeTab == 1 {
                                            Text("Carga \(snap.loadScore) · \(snap.state.rawValue)")
                                                .font(ImprovingFont.caption(13))
                                                .foregroundColor(snap.state.color)
                                        } else {
                                            HStack(spacing: 5) {
                                                Text(snap.state.rawValue)
                                                    .foregroundColor(snap.state.color)
                                                Text("•")
                                                    .foregroundColor(BevelColors.textMuted)
                                                Text("\(snap.freshnessPct) %")
                                                    .monospacedDigit()
                                                    .foregroundColor(BevelColors.textPrimary)
                                            }
                                            .font(ImprovingFont.caption(13.5))
                                            .fontWeight(.semibold)
                                        }
                                    }
                                    Spacer()
                                    MuscleBatteryBarsView(
                                        filledBars: snap.filledBars,
                                        color: snap.state.color,
                                        isCalibrating: snap.state == .calibrating
                                    )
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_mg_load",
                                badgeIcon: "scope",
                                heroTitle: "Carga muscular",
                                heroSubtitle: "Fundamentos",
                                cardTitle: "Fundamentos: Carga muscular",
                                cardDescription: "Entrena con propósito comprendiendo tu carga muscular.",
                                gradientHexA: 0x4E3F37,
                                gradientHexB: 0x242730,
                                fullGuideBody: "Tu carga muscular refleja el estrés mecánico acumulado en los últimos 7 y 28 días por grupo muscular."
                            ),
                            FitnessResourceItem(
                                id: "res_mg_fresh",
                                badgeIcon: "bolt.batteryblock.fill",
                                heroTitle: "Frescura muscular",
                                heroSubtitle: "Fundamentos",
                                cardTitle: "Fundamentos: Frescura muscular",
                                cardDescription: "Sabe cuándo apretar y cuándo dar descanso a cada músculo.",
                                gradientHexA: 0x4A4035,
                                gradientHexB: 0x22262E,
                                fullGuideBody: "Cada grupo muscular se recupera en 48–72 horas según la intensidad. Entrenar músculos recuperados en verde reduce el riesgo de lesión."
                            )
                        ])
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "mg_\(muscleModeTab)_\(muscleDateOffset)",
                metricTitle: "Grupos musculares",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "🌿"
            )
        }
    }

    // MARK: - Shared Helpers

    private var activityFilterChipsBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showActivitySearch.toggle()
                            if !showActivitySearch { activitySearchQuery = "" }
                        }
                    } label: {
                        Image(systemName: showActivitySearch ? "xmark" : "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(showActivitySearch ? .white : BevelColors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(showActivitySearch ? BevelColors.indigoEnd : BevelColors.cardSubtle))
                    }
                    .accessibilityLabel("Filtrar actividades por nombre")

                    let filteredNames = activitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? availableActivityNames
                        : availableActivityNames.filter { $0.localizedCaseInsensitiveContains(activitySearchQuery) || $0 == "Todas" }

                    ForEach(filteredNames, id: \.self) { name in
                        let active = selectedActivityFilter == name
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedActivityFilter = name
                        } label: {
                            Text(name)
                                .font(ImprovingFont.cardTitle(13))
                                .foregroundColor(active ? .white : BevelColors.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(active ? BevelColors.indigoEnd : BevelColors.cardSubtle))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if showActivitySearch {
                TextField("Buscar deporte o actividad…", text: $activitySearchQuery)
                    .font(ImprovingFont.body(14))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.card))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    .padding(.horizontal, 16)
            }
        }
    }

    private func muscleModePill(_ title: String, idx: Int) -> some View {
        let active = muscleModeTab == idx
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            muscleModeTab = idx
        } label: {
            Text(title)
                .font(ImprovingFont.cardTitle(13.5))
                .foregroundColor(active ? .white : BevelColors.textSecondary)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
        }
    }

    private func muscleFilterChip(title: String, dotColor: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 6) {
                if let c = dotColor {
                    Circle().fill(c).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(ImprovingFont.caption(13))
                    .fontWeight(.semibold)
                    .foregroundColor(active ? .white : BevelColors.textSecondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
        }
    }

    private func focusRow(_ label: String, val: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(ImprovingFont.body(14)).foregroundColor(BevelColors.textPrimary).frame(width: 96, alignment: .leading)
            Text(val).font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary).frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                    if pct > 0 {
                        Capsule().fill(color).frame(width: max(8, geo.size.width * CGFloat(pct) / 100.0), height: 8)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text("\(pct)%").font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func zoneExplainBullet(color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 6)
            (Text(title).fontWeight(.semibold).foregroundColor(BevelColors.textPrimary) + Text(" \(body)").foregroundColor(BevelColors.textSecondary))
                .font(ImprovingFont.body(13.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
