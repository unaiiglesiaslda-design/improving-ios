import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Compact JSON snapshot shared between the main Improving app and `ImprovingWidgets`
/// via App Group `UserDefaults` (with full AltStore / SideStore `ALTAppGroups` rewriting support!).
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
    var updatedAt: Date

    var isEmpty: Bool {
        strainPct == nil && recoveryPct == nil && sleepPct == nil && energyPct == nil && nutritionScore == nil
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
        updatedAt: Date()
    )
}

enum WidgetSnapshotStore {
    static let storageKey = "improving.widget.snapshot.v1"
    static let defaultAppGroup = "group.com.improving.health.ios"

    /// Sideload-safe App Group resolver: AltStore, SideStore, and LiveContainer rewrite
    /// entitlements with the signer's Team ID and advertise the provisioned group inside `ALTAppGroups`.
    static func resolveSuiteName(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let dict = infoDictionary ?? [:]
        let configured = (dict["AppGroupIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let altGroups = (dict["ALTAppGroups"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("group.") && !$0.isEmpty } ?? []

        if let configured, !configured.isEmpty,
           let provisioned = altGroups.first(where: { $0 == configured || $0.hasPrefix(configured + ".") }) {
            return provisioned
        }
        if altGroups.count == 1, let only = altGroups.first {
            return only
        }
        if let firstAlt = altGroups.first {
            return firstAlt
        }
        if let configured, !configured.isEmpty {
            return configured
        }
        return defaultAppGroup
    }

    private static func sharedDefaults() -> UserDefaults? {
        let suite = resolveSuiteName()
        if let d = UserDefaults(suiteName: suite) {
            return d
        }
        return UserDefaults.standard
    }

    static func save(_ snapshot: ImprovingWidgetSnapshot, triggerReload: Bool = true) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let defaults = sharedDefaults() {
            let previousData = defaults.data(forKey: storageKey)
            defaults.set(data, forKey: storageKey)
            // Also mirror to standard defaults as an extra fallback
            if defaults !== UserDefaults.standard {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
            if triggerReload {
                let changed: Bool = {
                    guard let prevData = previousData,
                          let prev = try? JSONDecoder().decode(ImprovingWidgetSnapshot.self, from: prevData) else {
                        return true
                    }
                    return prev.dateIso != snapshot.dateIso ||
                        prev.strainPct != snapshot.strainPct ||
                        prev.recoveryPct != snapshot.recoveryPct ||
                        prev.sleepPct != snapshot.sleepPct ||
                        prev.energyPct != snapshot.energyPct ||
                        prev.nutritionScore != snapshot.nutritionScore ||
                        prev.caloriesToday != snapshot.caloriesToday ||
                        prev.stressScore != snapshot.stressScore
                }()
                if changed {
                    #if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
                    #endif
                }
            }
        }
    }

    static func load() -> ImprovingWidgetSnapshot? {
        if let defaults = sharedDefaults(),
           let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ImprovingWidgetSnapshot.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ImprovingWidgetSnapshot.self, from: data) {
            return decoded
        }
        return nil
    }
}
