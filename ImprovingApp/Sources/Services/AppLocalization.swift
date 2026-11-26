import Foundation

/// Centralized `String(localized:)` facade providing Spanish defaults and a clean foundation
/// for future String Catalog (`.xcstrings`) multi-language localization.
enum L10n {
    static let tabHoy = String(localized: "tab.hoy", defaultValue: "Hoy")
    static let tabDiario = String(localized: "tab.diario", defaultValue: "Diario")
    static let tabFitness = String(localized: "tab.fitness", defaultValue: "Fitness")
    static let tabBiologia = String(localized: "tab.biologia", defaultValue: "Biología")

    static let coachTitle = String(localized: "coach.title", defaultValue: "Coach IA")
    static let noData = String(localized: "common.no_data", defaultValue: "Sin datos")
    static let done = String(localized: "common.done", defaultValue: "Listo")
    static let cancel = String(localized: "common.cancel", defaultValue: "Cancelar")
    static let save = String(localized: "common.save", defaultValue: "Guardar")
    static let close = String(localized: "common.close", defaultValue: "Cerrar")
    static let syncNow = String(localized: "sync.now", defaultValue: "Sincronizar")
    static let basics = String(localized: "resources.basics", defaultValue: "Fundamentos")
    static let yearToDate = String(localized: "range.ytd", defaultValue: "Año")
}
