import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Compact JSON snapshot shared between the main Improving app and `ImprovingWidgets`
/// via App Group shared container file (zero `cfprefsd` cache lag) + `UserDefaults(suiteName:)` backup.
/// Automatically discovers real provisioned App Groups from `embedded.mobileprovision`, `ALTAppGroups`
/// (AltStore / SideStore / LiveContainer), and `AppGroupIdentifier`.
struct ImprovingWidgetSnapshot: Codable, Equatable {
    var dateIso: String
    var dateLabel: String
    var strainPct: Int?
    var recoveryPct: Int?
    var sleepPct: Int?
    var energyPct: Int?
    var stressScore: Int?
    var hrvMs: Double?
    var restingHrBpm: Double?
    var sleepDurationText: String
    var nutritionScore: Int?
    var caloriesToday: Int
    var caloriesGoal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var stepsCount: Int?
    var optimalStrainLowPct: Int? = nil
    var optimalStrainHighPct: Int? = nil
    var updatedAt: Date

    var isEmpty: Bool {
        strainPct == nil && recoveryPct == nil && sleepPct == nil && energyPct == nil && nutritionScore == nil
    }

    enum CodingKeys: String, CodingKey {
        case dateIso, dateLabel, strainPct, recoveryPct, sleepPct, energyPct, stressScore
        case hrvMs, restingHrBpm, sleepDurationText, nutritionScore
        case caloriesToday, caloriesGoal, proteinG, carbsG, fatG, stepsCount
        case optimalStrainLowPct, optimalStrainHighPct, updatedAt
    }

    init(
        dateIso: String,
        dateLabel: String,
        strainPct: Int?,
        recoveryPct: Int?,
        sleepPct: Int?,
        energyPct: Int?,
        stressScore: Int?,
        hrvMs: Double?,
        restingHrBpm: Double?,
        sleepDurationText: String,
        nutritionScore: Int?,
        caloriesToday: Int,
        caloriesGoal: Int,
        proteinG: Int,
        carbsG: Int,
        fatG: Int,
        stepsCount: Int?,
        optimalStrainLowPct: Int? = nil,
        optimalStrainHighPct: Int? = nil,
        updatedAt: Date
    ) {
        self.dateIso = dateIso
        self.dateLabel = dateLabel
        self.strainPct = strainPct
        self.recoveryPct = recoveryPct
        self.sleepPct = sleepPct
        self.energyPct = energyPct
        self.stressScore = stressScore
        self.hrvMs = hrvMs
        self.restingHrBpm = restingHrBpm
        self.sleepDurationText = sleepDurationText
        self.nutritionScore = nutritionScore
        self.caloriesToday = caloriesToday
        self.caloriesGoal = caloriesGoal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.stepsCount = stepsCount
        self.optimalStrainLowPct = optimalStrainLowPct
        self.optimalStrainHighPct = optimalStrainHighPct
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateIso = try c.decodeIfPresent(String.self, forKey: .dateIso) ?? ""
        dateLabel = try c.decodeIfPresent(String.self, forKey: .dateLabel) ?? "Hoy"
        strainPct = try c.decodeIfPresent(Int.self, forKey: .strainPct)
        recoveryPct = try c.decodeIfPresent(Int.self, forKey: .recoveryPct)
        sleepPct = try c.decodeIfPresent(Int.self, forKey: .sleepPct)
        energyPct = try c.decodeIfPresent(Int.self, forKey: .energyPct)
        stressScore = try c.decodeIfPresent(Int.self, forKey: .stressScore)
        hrvMs = try c.decodeIfPresent(Double.self, forKey: .hrvMs)
        restingHrBpm = try c.decodeIfPresent(Double.self, forKey: .restingHrBpm)
        sleepDurationText = try c.decodeIfPresent(String.self, forKey: .sleepDurationText) ?? "--"
        nutritionScore = try c.decodeIfPresent(Int.self, forKey: .nutritionScore)
        caloriesToday = try c.decodeIfPresent(Int.self, forKey: .caloriesToday) ?? 0
        caloriesGoal = try c.decodeIfPresent(Int.self, forKey: .caloriesGoal) ?? 2200
        proteinG = try c.decodeIfPresent(Int.self, forKey: .proteinG) ?? 0
        carbsG = try c.decodeIfPresent(Int.self, forKey: .carbsG) ?? 0
        fatG = try c.decodeIfPresent(Int.self, forKey: .fatG) ?? 0
        stepsCount = try c.decodeIfPresent(Int.self, forKey: .stepsCount)
        optimalStrainLowPct = try c.decodeIfPresent(Int.self, forKey: .optimalStrainLowPct)
        optimalStrainHighPct = try c.decodeIfPresent(Int.self, forKey: .optimalStrainHighPct)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    static let placeholder = ImprovingWidgetSnapshot(
        dateIso: "2026-11-25",
        dateLabel: "Hoy",
        strainPct: 58,
        recoveryPct: 82,
        sleepPct: 88,
        energyPct: 76,
        stressScore: 28,
        hrvMs: 72.4,
        restingHrBpm: 51.0,
        sleepDurationText: "7h 45m",
        nutritionScore: 84,
        caloriesToday: 1620,
        caloriesGoal: 2200,
        proteinG: 124,
        carbsG: 168,
        fatG: 54,
        stepsCount: 7420,
        optimalStrainLowPct: 48,
        optimalStrainHighPct: 72,
        updatedAt: Date()
    )
}

struct WidgetBridgeDiagnostic: Equatable {
    let resolvedGroup: String
    let candidateGroups: [String]
    let provisionedFromProfile: [String]
    let sharedContainerAvailable: Bool
    let snapshotFilePresent: Bool
    let lastUpdatedAt: Date?
}

enum WidgetSnapshotStore {
    static let storageKey = "improving.widget.snapshot.v1"
    static let fileName = "improving_widget_snapshot_v1.json"
    static let defaultAppGroup = "group.com.improving.health.ios"

    /// Extracts real provisioned `com.apple.security.application-groups` directly from `embedded.mobileprovision`
    /// so Sideloadly, AltStore, SideStore, Feather, ESign, and Xcode builds all discover their exact group IDs!
    static func extractAppGroupsFromMobileProvision(data: Data) -> [String] {
        guard let raw = String(data: data, encoding: .isoLatin1),
              let xmlStart = raw.range(of: "<?xml"),
              let plistEnd = raw.range(of: "</plist>", range: xmlStart.lowerBound..<raw.endIndex),
              let plistData = String(raw[xmlStart.lowerBound..<plistEnd.upperBound]).data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return []
        }
        return groups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("group.") && !$0.isEmpty }
    }

    private static func provisionedGroupsFromBundle(at bundleURL: URL) -> [String] {
        let mpURL = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: mpURL) else { return [] }
        return extractAppGroupsFromMobileProvision(data: data)
    }

    private static func parentAppBundleURLIfExtension() -> URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension.lowercased() == "appex" else { return nil }
        let parent = url.deletingLastPathComponent().deletingLastPathComponent()
        return parent.pathExtension.lowercased() == "app" ? parent : nil
    }

    /// Returns all candidate App Group identifiers in strict priority order:
    /// 1. Real entitlements in `embedded.mobileprovision` (self + parent `.app` when running as `.appex`)
    /// 2. `ALTAppGroups` in `Info.plist` (self + parent `.app`)
    /// 3. `AppGroupIdentifier` in `Info.plist`
    /// 4. `group.<parentBundleId>` dynamic derivation + `defaultAppGroup`
    static func candidateSuiteNames(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        provisionedOverride: [String]? = nil
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func add(_ raw: String?) {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  s.hasPrefix("group."), !s.isEmpty else { return }
            if seen.insert(s).inserted { ordered.append(s) }
        }

        // 1. Real provisioned entitlements from embedded.mobileprovision
        let prov = provisionedOverride ?? {
            var list = provisionedGroupsFromBundle(at: Bundle.main.bundleURL)
            if let parentURL = parentAppBundleURLIfExtension() {
                list.append(contentsOf: provisionedGroupsFromBundle(at: parentURL))
            }
            return list
        }()
        for g in prov { add(g) }

        // 2. ALTAppGroups & AppGroupIdentifier from Bundle Info.plist (+ parent app if extension)
        var dicts: [[String: Any]] = []
        if let d = infoDictionary { dicts.append(d) }
        if provisionedOverride == nil,
           let parentURL = parentAppBundleURLIfExtension(),
           let parentBundle = Bundle(url: parentURL),
           let parentInfo = parentBundle.infoDictionary {
            dicts.append(parentInfo)
        }

        for dict in dicts {
            let configured = (dict["AppGroupIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let altGroups = (dict["ALTAppGroups"] as? [String])?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("group.") && !$0.isEmpty } ?? []
            if let configured, !configured.isEmpty,
               let match = altGroups.first(where: { $0 == configured || $0.hasPrefix(configured + ".") }) {
                add(match)
            }
            for g in altGroups { add(g) }
            add(configured)
        }

        // 3. Dynamic derivation from current bundle identifier (handles signers renaming bundle ID + group)
        if let rawBid = (infoDictionary?["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawBid.isEmpty {
            var baseBid = rawBid
            for suffix in [".widgets", ".ImprovingWidgets", ".widget"] {
                if baseBid.hasSuffix(suffix) {
                    baseBid = String(baseBid.dropLast(suffix.count))
                    break
                }
            }
            add("group.\(baseBid)")
        }

        add(defaultAppGroup)
        return ordered
    }

    /// Primary resolved App Group suite name (prefers groups whose container URL is actually provisioned by iOS!).
    static func resolveSuiteName(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        provisionedOverride: [String]? = nil
    ) -> String {
        let candidates = candidateSuiteNames(infoDictionary: infoDictionary, provisionedOverride: provisionedOverride)
        if provisionedOverride == nil {
            for g in candidates {
                if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
                    return g
                }
            }
        }
        return candidates.first ?? defaultAppGroup
    }

    private static func snapshotFileURL(forGroup groupId: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent(fileName)
    }

    static func diagnosticStatus() -> WidgetBridgeDiagnostic {
        let prov = provisionedGroupsFromBundle(at: Bundle.main.bundleURL)
        let candidates = candidateSuiteNames()
        let resolved = resolveSuiteName()
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolved)
        let fileURL = containerURL?.appendingPathComponent(fileName)
        let exists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let loaded = load()
        return WidgetBridgeDiagnostic(
            resolvedGroup: resolved,
            candidateGroups: candidates,
            provisionedFromProfile: prov,
            sharedContainerAvailable: containerURL != nil,
            snapshotFilePresent: exists,
            lastUpdatedAt: loaded?.updatedAt
        )
    }

    static func save(_ snapshot: ImprovingWidgetSnapshot, triggerReload: Bool = true, forceReload: Bool = false) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let prevSnap = load()
        let candidates = candidateSuiteNames()
        var wroteToSharedContainer = false

        // 1. Write atomic JSON file into EVERY provisioned App Group container (immune to cfprefsd caching!)
        for groupId in candidates {
            if let url = snapshotFileURL(forGroup: groupId) {
                do {
                    try data.write(to: url, options: .atomic)
                    wroteToSharedContainer = true
                } catch {}
            }
        }

        // 2. Also write into UserDefaults(suiteName:) for each valid/resolved group + standard fallback
        let primarySuite = resolveSuiteName()
        let suitesToWrite = wroteToSharedContainer
            ? candidates.filter { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
            : [primarySuite]

        for suite in suitesToWrite {
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.set(data, forKey: storageKey)
                defaults.synchronize()
            }
        }
        UserDefaults.standard.set(data, forKey: storageKey)

        guard triggerReload else { return }
        let contentChanged: Bool = {
            guard let prev = prevSnap else { return true }
            return prev.dateIso != snapshot.dateIso ||
                prev.dateLabel != snapshot.dateLabel ||
                prev.strainPct != snapshot.strainPct ||
                prev.recoveryPct != snapshot.recoveryPct ||
                prev.sleepPct != snapshot.sleepPct ||
                prev.energyPct != snapshot.energyPct ||
                prev.stressScore != snapshot.stressScore ||
                prev.hrvMs != snapshot.hrvMs ||
                prev.restingHrBpm != snapshot.restingHrBpm ||
                prev.sleepDurationText != snapshot.sleepDurationText ||
                prev.nutritionScore != snapshot.nutritionScore ||
                prev.caloriesToday != snapshot.caloriesToday ||
                prev.proteinG != snapshot.proteinG ||
                prev.carbsG != snapshot.carbsG ||
                prev.fatG != snapshot.fatG ||
                prev.stepsCount != snapshot.stepsCount ||
                prev.optimalStrainLowPct != snapshot.optimalStrainLowPct ||
                prev.optimalStrainHighPct != snapshot.optimalStrainHighPct
        }()

        if forceReload || contentChanged {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "ImprovingResumenWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ImprovingNutricionWidget")
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    static func load() -> ImprovingWidgetSnapshot? {
        let candidates = candidateSuiteNames()
        let decoder = JSONDecoder()
        var freshest: ImprovingWidgetSnapshot? = nil

        // 1. Primary: Read direct JSON files from provisioned App Group containers (instant, zero cfprefsd lag!)
        for groupId in candidates {
            if let url = snapshotFileURL(forGroup: groupId),
               let data = try? Data(contentsOf: url),
               let decoded = try? decoder.decode(ImprovingWidgetSnapshot.self, from: data) {
                if freshest == nil || decoded.updatedAt > freshest!.updatedAt {
                    freshest = decoded
                }
            }
        }
        if let freshest { return freshest }

        // 2. Secondary: Read UserDefaults(suiteName:) across candidate groups
        for groupId in candidates {
            if let defaults = UserDefaults(suiteName: groupId),
               let data = defaults.data(forKey: storageKey),
               let decoded = try? decoder.decode(ImprovingWidgetSnapshot.self, from: data) {
                if freshest == nil || decoded.updatedAt > freshest!.updatedAt {
                    freshest = decoded
                }
            }
        }
        if let freshest { return freshest }

        // 3. Fallback: standard UserDefaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode(ImprovingWidgetSnapshot.self, from: data) {
            return decoded
        }
        return nil
    }
}
