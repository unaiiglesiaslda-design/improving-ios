import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct ImprovingWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ImprovingWidgetSnapshot
    let hasLiveSnapshot: Bool
    var isStaleDay: Bool = false
}

struct ImprovingWidgetProvider: TimelineProvider {
    private static func isoDay(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    private static func adjustedSnapshot(_ raw: ImprovingWidgetSnapshot, for entryDate: Date) -> (snap: ImprovingWidgetSnapshot, isStale: Bool) {
        let todayIso = isoDay(for: entryDate)
        guard !raw.dateIso.isEmpty && raw.dateIso != todayIso else {
            return (raw, false)
        }
        // Midnight rollover: never display yesterday's calories/strain labeled as "Hoy"!
        let rolled = ImprovingWidgetSnapshot(
            dateIso: raw.dateIso,
            dateLabel: "Ayer",
            strainPct: 0,
            recoveryPct: raw.recoveryPct,
            sleepPct: raw.sleepPct,
            energyPct: raw.energyPct,
            stressScore: nil,
            hrvMs: raw.hrvMs,
            restingHrBpm: raw.restingHrBpm,
            sleepDurationText: raw.sleepDurationText,
            nutritionScore: nil,
            caloriesToday: 0,
            caloriesGoal: raw.caloriesGoal,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            stepsCount: nil,
            optimalStrainLowPct: raw.optimalStrainLowPct,
            optimalStrainHighPct: raw.optimalStrainHighPct,
            updatedAt: raw.updatedAt
        )
        return (rolled, true)
    }

    func placeholder(in context: Context) -> ImprovingWidgetEntry {
        ImprovingWidgetEntry(date: Date(), snapshot: .placeholder, hasLiveSnapshot: true, isStaleDay: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ImprovingWidgetEntry) -> Void) {
        let now = Date()
        if let loaded = WidgetSnapshotStore.load() {
            let adj = Self.adjustedSnapshot(loaded, for: now)
            completion(ImprovingWidgetEntry(date: now, snapshot: adj.snap, hasLiveSnapshot: true, isStaleDay: adj.isStale))
        } else {
            // Fixed inverted preview flag: Widget Gallery previews show clean sample rings, real empty widgets prompt to open app!
            completion(ImprovingWidgetEntry(date: now, snapshot: .placeholder, hasLiveSnapshot: context.isPreview, isStaleDay: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ImprovingWidgetEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(3600 * 12)
        let loaded = WidgetSnapshotStore.load()

        guard let raw = loaded else {
            let emptySnap = ImprovingWidgetSnapshot(
                dateIso: "",
                dateLabel: "Hoy",
                strainPct: 0,
                recoveryPct: nil,
                sleepPct: nil,
                energyPct: nil,
                stressScore: nil,
                hrvMs: nil,
                restingHrBpm: nil,
                sleepDurationText: "--",
                nutritionScore: nil,
                caloriesToday: 0,
                caloriesGoal: 2200,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                stepsCount: nil,
                optimalStrainLowPct: 42,
                optimalStrainHighPct: 64,
                updatedAt: now
            )
            let entry = ImprovingWidgetEntry(date: now, snapshot: emptySnap, hasLiveSnapshot: false, isStaleDay: false)
            // Respect WidgetKit daily budget: refresh at next midnight (main app pushes immediate reloads when data changes!)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
            return
        }

        let currentAdj = Self.adjustedSnapshot(raw, for: now)
        let currentEntry = ImprovingWidgetEntry(date: now, snapshot: currentAdj.snap, hasLiveSnapshot: true, isStaleDay: currentAdj.isStale)
        let midnightAdj = Self.adjustedSnapshot(raw, for: nextMidnight)
        let midnightEntry = ImprovingWidgetEntry(date: nextMidnight, snapshot: midnightAdj.snap, hasLiveSnapshot: true, isStaleDay: midnightAdj.isStale)
        completion(Timeline(entries: [currentEntry, midnightEntry], policy: .after(nextMidnight)))
    }
}

// MARK: - Shared Widget Palette & Static Vector Ring (Zero onAppear Animation for WidgetKit!)

private enum WidgetPalette {
    static let bgTop = Color(red: 0.11, green: 0.13, blue: 0.17)
    static let bgBottom = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let cardFill = Color.white.opacity(0.07)
    static let strain = Color(red: 0.98, green: 0.64, blue: 0.24)
    static let recovery = Color(red: 0.23, green: 0.84, blue: 0.44)
    static let sleep = Color(red: 0.55, green: 0.65, blue: 0.97)
    static let energy = Color(red: 0.34, green: 0.85, blue: 0.60)
    static let nutrition = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let fat = Color(red: 0.43, green: 0.58, blue: 0.96)
    static let carbs = Color(red: 0.96, green: 0.65, blue: 0.14)
    static let protein = Color(red: 0.91, green: 0.36, blue: 0.59)
}

private struct StaticWidgetRing: View {
    let value: Int?
    let label: String
    let color: Color
    let diameter: CGFloat
    let lineWidth: CGFloat
    var showZeroNub: Bool = false
    var optimalRange: ClosedRange<Double>? = nil

    var body: some View {
        let effectiveVal: Int? = value ?? (showZeroNub ? 0 : nil)
        let progress: Double = {
            if let v = effectiveVal {
                if v <= 0 { return showZeroNub ? 0.028 : 0.0 }
                return min(max(Double(v) / 100.0, 0.03), 1.0)
            }
            return 0.0
        }()

        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.11), lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)

                if let range = optimalRange, range.upperBound > range.lowerBound {
                    Circle()
                        .trim(from: CGFloat(range.lowerBound), to: CGFloat(range.upperBound))
                        .stroke(Color.white.opacity(0.24), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter, height: diameter)
                }

                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter, height: diameter)
                }

                Text(effectiveVal.map { "\($0)" } ?? "--")
                    .font(.system(size: diameter * 0.28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(effectiveVal != nil ? .white : .white.opacity(0.45))
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)
        }
    }
}

// MARK: - Widget 1: Resumen Diario (3 Anillos + Batería Corporal + Lock Screen)

struct ImprovingResumenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: ImprovingWidgetEntry

    private var strainOptimalRange: ClosedRange<Double>? {
        let s = entry.snapshot
        guard let lo = s.optimalStrainLowPct, let hi = s.optimalStrainHighPct, hi > lo else { return nil }
        return (Double(lo) / 100.0)...(Double(hi) / 100.0)
    }

    private static let hhmmFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var syncTimeLabel: String {
        Self.hhmmFmt.string(from: entry.snapshot.updatedAt)
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallHomeView
            case .systemMedium:
                mediumHomeView
            case .accessoryCircular:
                lockScreenCircular
            case .accessoryRectangular:
                lockScreenRectangular
            default:
                smallHomeView
            }
        }
        .widgetURL(URL(string: "improving://hoy"))
    }

    private var smallHomeView: some View {
        let s = entry.snapshot
        let energyFrac = min(max(Double(s.energyPct ?? 0) / 100.0, 0.0), 1.0)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Improving")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text(entry.hasLiveSnapshot ? s.dateLabel : "Abrir app")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                StaticWidgetRing(
                    value: s.strainPct,
                    label: "Esf.",
                    color: WidgetPalette.strain,
                    diameter: 38,
                    lineWidth: 4.5,
                    showZeroNub: true,
                    optimalRange: strainOptimalRange
                )
                .frame(maxWidth: .infinity)
                StaticWidgetRing(value: s.recoveryPct, label: "Rec.", color: WidgetPalette.recovery, diameter: 38, lineWidth: 4.5)
                    .frame(maxWidth: .infinity)
                StaticWidgetRing(value: s.sleepPct, label: "Sueño", color: WidgetPalette.sleep, diameter: 38, lineWidth: 4.5)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(WidgetPalette.energy)
                    Text("Batería")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    Text(s.energyPct.map { "\($0)%" } ?? "--")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        if s.energyPct != nil {
                            Capsule()
                                .fill(LinearGradient(colors: [WidgetPalette.recovery, WidgetPalette.energy], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * CGFloat(energyFrac)))
                        }
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(WidgetPalette.cardFill))
        }
        .padding(2)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [WidgetPalette.bgTop, WidgetPalette.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var mediumHomeView: some View {
        let s = entry.snapshot
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(entry.hasLiveSnapshot ? WidgetPalette.recovery : WidgetPalette.strain).frame(width: 7, height: 7)
                    Text(entry.hasLiveSnapshot ? "Improving · \(s.dateLabel) · \(syncTimeLabel)" : "Abre Improving para sincronizar")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    StaticWidgetRing(
                        value: s.strainPct,
                        label: "Esfuerzo",
                        color: WidgetPalette.strain,
                        diameter: 48,
                        lineWidth: 5.5,
                        showZeroNub: true,
                        optimalRange: strainOptimalRange
                    )
                    StaticWidgetRing(value: s.recoveryPct, label: "Recup.", color: WidgetPalette.recovery, diameter: 48, lineWidth: 5.5)
                    StaticWidgetRing(value: s.sleepPct, label: "Sueño", color: WidgetPalette.sleep, diameter: 48, lineWidth: 5.5)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(WidgetPalette.energy)
                    Text("Batería \(s.energyPct.map { "\($0)%" } ?? "--")")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let stress = s.stressScore {
                        Text("· Estrés \(stress)")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            VStack(spacing: 7) {
                mediumStatPill(icon: "waveform.path.ecg", label: "VFC", value: s.hrvMs.map { String(format: "%.0f ms", $0) } ?? "--", color: WidgetPalette.recovery)
                mediumStatPill(icon: "heart.fill", label: "FCR", value: s.restingHrBpm.map { String(format: "%.0f ppm", $0) } ?? "--", color: Color(red: 0.96, green: 0.44, blue: 0.44))
                mediumStatPill(icon: "fork.knife", label: "Nutrición", value: s.nutritionScore.map { "\($0)/100" } ?? "--", color: WidgetPalette.nutrition)
            }
            .frame(width: 114)
        }
        .padding(2)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [WidgetPalette.bgTop, WidgetPalette.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func mediumStatPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WidgetPalette.cardFill))
    }

    private var lockScreenCircular: some View {
        let s = entry.snapshot
        let val = s.recoveryPct ?? s.energyPct ?? s.sleepPct
        let prog = val.map { min(max(Double($0) / 100.0, 0.02), 1.0) } ?? 0.0
        let ringColor: Color = (renderingMode == .fullColor) ? WidgetPalette.recovery : .primary

        return ZStack {
            AccessoryWidgetBackground()
            Circle()
                .stroke(.secondary.opacity(0.3), lineWidth: 5)
                .padding(4)
            if prog > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(prog))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            }
            VStack(spacing: 0) {
                Text(val.map { "\($0)" } ?? "--")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(s.recoveryPct != nil ? "REC" : (s.energyPct != nil ? "BAT" : "SUE"))
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .opacity(0.75)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var lockScreenRectangular: some View {
        let s = entry.snapshot
        let strainDisplay = "\(s.strainPct ?? 0)%"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .bold))
                Text("Improving")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                if let bat = s.energyPct {
                    Text("⚡\(bat)%")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            HStack(spacing: 10) {
                Text("Rec \(s.recoveryPct.map { "\($0)%" } ?? "--")")
                Text("Sue \(s.sleepPct.map { "\($0)%" } ?? "--")")
                Text("Esf \(strainDisplay)")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()

            Text("Sueño \(s.sleepDurationText) · VFC \(s.hrvMs.map { "\(Int($0.rounded()))ms" } ?? "--")")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.75)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget 2: Nutrición de Hoy (Puntuación + Calorías + Macros)

struct ImprovingNutricionWidgetView: View {
    let entry: ImprovingWidgetEntry

    var body: some View {
        let s = entry.snapshot
        let scoreProg = s.nutritionScore.map { min(max(Double($0) / 100.0, 0.03), 1.0) } ?? 0.0

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(WidgetPalette.nutrition)
                Text("Nutrición")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(s.caloriesToday) kcal")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.11), lineWidth: 6)
                        .frame(width: 56, height: 56)
                    if scoreProg > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(scoreProg))
                            .stroke(WidgetPalette.nutrition, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 56, height: 56)
                    }
                    Text(s.nutritionScore.map { "\($0)" } ?? "--")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    macroRow("G", val: "\(s.fatG)g", color: WidgetPalette.fat)
                    macroRow("C", val: "\(s.carbsG)g", color: WidgetPalette.carbs)
                    macroRow("P", val: "\(s.proteinG)g", color: WidgetPalette.protein)
                }
            }

            Spacer(minLength: 0)

            let rem = max(s.caloriesGoal - s.caloriesToday, 0)
            Text(!entry.hasLiveSnapshot ? "Abre Improving" : (entry.isStaleDay ? "Nuevo día · Sincroniza" : (s.caloriesToday == 0 ? "Sin comidas hoy" : "Faltan \(rem) kcal")))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(2)
        .widgetURL(URL(string: "improving://nutrition"))
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.14, green: 0.14, blue: 0.21), WidgetPalette.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func macroRow(_ tag: String, val: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(tag)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(val)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
    }
}

// MARK: - Widget Definitions & Bundle Entry Point

struct ImprovingResumenWidget: Widget {
    let kind: String = "ImprovingResumenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ImprovingWidgetProvider()) { entry in
            ImprovingResumenWidgetView(entry: entry)
        }
        .configurationDisplayName("Improving · Resumen")
        .description("Esfuerzo, Recuperación, Sueño y Batería Corporal en vivo.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ImprovingNutricionWidget: Widget {
    let kind: String = "ImprovingNutricionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ImprovingWidgetProvider()) { entry in
            ImprovingNutricionWidgetView(entry: entry)
        }
        .configurationDisplayName("Improving · Nutrición")
        .description("Puntuación nutricional, calorías y macros del día.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ImprovingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ImprovingResumenWidget()
        ImprovingNutricionWidget()
    }
}
