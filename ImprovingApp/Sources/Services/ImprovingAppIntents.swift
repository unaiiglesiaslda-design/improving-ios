import Foundation
import AppIntents

/// Native iOS Apple Shortcuts (`Atajos`) action — requires ZERO paid Apple Developer entitlements!
/// Runs silently in the background (`openAppWhenRun = false`) when triggered by an iOS Personal Automation
/// (e.g. every 4 hours, every morning, or when opening Improving) and delivers real Apple Health samples straight into Improving.
struct SyncAppleHealthShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Sincronizar Salud en Improving"
    static var description: IntentDescription? = IntentDescription(
        "Envía automáticamente tus muestras reales de Apple Salud (VFC, FC, FCR, Sueño, FR, SpO₂, Temperatura, Pasos y Calorías) a Improving sin cuenta de pago."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Valores de FC (ppm)", description: "Lista de valores de 'Buscar muestras de Salud' (Frecuencia cardíaca → Valor)")
    var hrValues: [String]?

    @Parameter(title: "Fechas de FC", description: "Fechas de 'Buscar muestras de Salud' (Frecuencia cardíaca → Fecha de inicio)")
    var hrDates: [String]?

    @Parameter(title: "Valores de VFC (ms)", description: "Valores de Variabilidad de la frecuencia cardíaca")
    var hrvValues: [String]?

    @Parameter(title: "Fechas de VFC", description: "Fechas de Variabilidad de la frecuencia cardíaca")
    var hrvDates: [String]?

    @Parameter(title: "Valores de FC en reposo", description: "Valores de Frecuencia cardíaca en reposo")
    var rhrValues: [String]?

    @Parameter(title: "Fechas de FC en reposo", description: "Fechas de Frecuencia cardíaca en reposo")
    var rhrDates: [String]?

    @Parameter(title: "Fases de Sueño", description: "Valores de Sueño (Profundo, REM, Esencial, Despierto, En cama)")
    var sleepValues: [String]?

    @Parameter(title: "Inicios de Sueño", description: "Fecha de inicio de cada muestra de Sueño")
    var sleepStarts: [String]?

    @Parameter(title: "Fines de Sueño", description: "Fecha de finalización de cada muestra de Sueño")
    var sleepEnds: [String]?

    @Parameter(title: "Valores de Frecuencia respiratoria", description: "Valores de Frecuencia respiratoria")
    var respValues: [String]?

    @Parameter(title: "Fechas de Frecuencia respiratoria")
    var respDates: [String]?

    @Parameter(title: "Valores de SpO₂ (%)", description: "Valores de Oxígeno en sangre")
    var spo2Values: [String]?

    @Parameter(title: "Fechas de SpO₂")
    var spo2Dates: [String]?

    @Parameter(title: "Temperatura muñeca (°C)", description: "Valores de Temperatura de la muñeca al dormir")
    var tempValues: [String]?

    @Parameter(title: "Fechas de Temperatura")
    var tempDates: [String]?

    @Parameter(title: "Valores de Pasos")
    var stepsValues: [String]?

    @Parameter(title: "Fechas de Pasos")
    var stepsDates: [String]?

    @Parameter(title: "Calorías activas (kcal)")
    var kcalValues: [String]?

    @Parameter(title: "Fechas de Calorías activas")
    var kcalDates: [String]?

    @Parameter(title: "JSON o texto libre (opcional)", description: "Alternativa: pega aquí un Diccionario JSON o líneas tipo 'hrv|fecha|valor'")
    var rawTextOrJson: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let envelope = ShortcutsSyncEnvelope(
            source: "Atajos de Apple",
            createdAtEpoch: Int64(Date().timeIntervalSince1970),
            hrValues: hrValues,
            hrDates: hrDates,
            hrvValues: hrvValues,
            hrvDates: hrvDates,
            rhrValues: rhrValues,
            rhrDates: rhrDates,
            respValues: respValues,
            respDates: respDates,
            spo2Values: spo2Values,
            spo2Dates: spo2Dates,
            tempValues: tempValues,
            tempDates: tempDates,
            stepsValues: stepsValues,
            stepsDates: stepsDates,
            kcalValues: kcalValues,
            kcalDates: kcalDates,
            sleepValues: sleepValues,
            sleepStarts: sleepStarts,
            sleepEnds: sleepEnds,
            rawTextOrJson: rawTextOrJson
        )

        guard ShortcutsHealthSyncImporter.saveEnvelopeToInbox(envelope) != nil else {
            return .result(value: "No se pudo guardar la sincronización en Improving.")
        }
        return .result(value: "✓ Datos de Apple Salud enviados a Improving.")
    }
}

struct ImprovingAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncAppleHealthShortcutIntent(),
            phrases: [
                "Sincronizar salud en \(.applicationName)",
                "Enviar datos de salud a \(.applicationName)"
            ],
            shortTitle: "Sincronizar Salud",
            systemImageName: "heart.text.square.fill"
        )
    }
}
