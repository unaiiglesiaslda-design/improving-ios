import Foundation
import UserNotifications

struct ComputedSleepNotificationPlan: Equatable {
    let bedtimeHour: Int
    let bedtimeMinute: Int
    let bedtimeLabel: String
    let notifyHour: Int
    let notifyMinute: Int
    let notifyLabel: String
    let wakeLabel: String
    let sleepNeedLabel: String
}

@MainActor
final class LocalNotificationManager {
    static let shared = LocalNotificationManager()

    private let bedtimeId = "com.improving.notif.sleep.bedtime"
    private let smartAlarmId = "com.improving.notif.sleep.smartalarm"
    private let testId = "com.improving.notif.test"
    private let journalDayPrefix = "com.improving.notif.journal.d"

    private var managedIdentifiers: [String] {
        var ids = [bedtimeId, smartAlarmId, "com.improving.notif.journal.daily"]
        for i in 0...7 {
            ids.append("\(journalDayPrefix)\(i)")
        }
        return ids
    }

    nonisolated static func computeSleepNotificationPlan(
        wakeHour: Int,
        wakeMinute: Int,
        sleepNeedMinutes: Int,
        leadMinutes: Int
    ) -> ComputedSleepNotificationPlan {
        let clampedNeed = min(max(sleepNeedMinutes, 300), 720)
        let clampedLead = min(max(leadMinutes, 0), 120)
        let wakeTotal = (((wakeHour * 60 + wakeMinute) % 1440) + 1440) % 1440
        let bedTotal = (((wakeTotal - clampedNeed) % 1440) + 1440) % 1440
        let notifyTotal = (((bedTotal - clampedLead) % 1440) + 1440) % 1440

        let bedH = bedTotal / 60
        let bedM = bedTotal % 60
        let notH = notifyTotal / 60
        let notM = notifyTotal % 60
        let wakeH = wakeTotal / 60
        let wakeM = wakeTotal % 60

        let needH = clampedNeed / 60
        let needM = clampedNeed % 60

        return ComputedSleepNotificationPlan(
            bedtimeHour: bedH,
            bedtimeMinute: bedM,
            bedtimeLabel: String(format: "%02d:%02d", bedH, bedM),
            notifyHour: notH,
            notifyMinute: notM,
            notifyLabel: String(format: "%02d:%02d", notH, notM),
            wakeLabel: String(format: "%02d:%02d", wakeH, wakeM),
            sleepNeedLabel: "\(needH) h \(String(format: "%02d", needM)) min"
        )
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func syncAllSchedules(
        settings: SmartNotificationSettings,
        smartAlarmEnabled: Bool,
        todayJournalAlreadyLogged: Bool,
        sleepNeedMinutes: Int,
        sleepDebtMinutes: Int,
        strainPercent: Int,
        hasStrainData: Bool,
        userName: String,
        promptPermissionIfNeeded: Bool
    ) async -> String {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)

        let anyEnabled = settings.journalReminderEnabled || settings.bedtimeReminderEnabled || smartAlarmEnabled
        guard anyEnabled else {
            return "Avisos automáticos desactivados"
        }

        let allowed: Bool
        if promptPermissionIfNeeded {
            allowed = await requestAuthorizationIfNeeded()
        } else {
            let st = await authorizationStatus()
            allowed = (st == .authorized || st == .provisional || st == .ephemeral)
        }

        guard allowed else {
            let st = await authorizationStatus()
            if st == .denied {
                return "Permiso denegado · Actívalo en Ajustes de iOS → Notificaciones → Improving"
            }
            return "Pulsa un aviso o «Probar notificación» para autorizar notificaciones en iOS"
        }

        let cleanName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadName = cleanName.isEmpty ? "" : "\(cleanName), "
        var activeParts: [String] = []
        let cal = Calendar.current
        let now = Date()

        // 1. Nightly Diario Reminder (skips tonight automatically if today's Diario already has entries!)
        if settings.journalReminderEnabled {
            let startOffset = todayJournalAlreadyLogged ? 1 : 0
            for dayOffset in startOffset...7 {
                guard let targetDay = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: targetDay)
                comps.hour = min(max(settings.journalReminderHour, 0), 23)
                comps.minute = min(max(settings.journalReminderMinute, 0), 59)
                comps.second = 0

                if let scheduledDate = cal.date(from: comps), scheduledDate <= now {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = "📓 Completa tu Diario de hoy"
                content.body = "\(leadName)marca tus hábitos y añade una nota rápida antes de dormir para que tu Coach IA analice tu VFC y descanso de mañana."
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(
                    identifier: "\(journalDayPrefix)\(dayOffset)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(req)
            }
            let hhmm = String(format: "%02d:%02d", settings.journalReminderHour, settings.journalReminderMinute)
            activeParts.append(todayJournalAlreadyLogged ? "Diario \(hhmm) (hoy ✓)" : "Diario \(hhmm)")
        }

        // 2. Smart Bedtime Notification based on real Sleep Debt + today's Strain
        let plan = Self.computeSleepNotificationPlan(
            wakeHour: settings.smartAlarmHour,
            wakeMinute: settings.smartAlarmMinute,
            sleepNeedMinutes: sleepNeedMinutes,
            leadMinutes: settings.bedtimeLeadMinutes
        )

        if settings.bedtimeReminderEnabled {
            var detailPieces: [String] = []
            if sleepDebtMinutes > 0 {
                detailPieces.append("deuda +\(sleepDebtMinutes) min")
            }
            if hasStrainData && strainPercent > 0 {
                detailPieces.append("esfuerzo \(strainPercent)%")
            }
            let detailClause = detailPieces.isEmpty ? "" : " (\(detailPieces.joined(separator: ", ")))"

            let content = UNMutableNotificationContent()
            content.title = "🌙 Hora recomendada de dormir: \(plan.bedtimeLabel)"
            content.body = "\(leadName)tu cuerpo necesita \(plan.sleepNeedLabel) esta noche\(detailClause) para despertar recuperado a las \(plan.wakeLabel). Empieza a bajar estímulos ahora."
            content.sound = .default

            var comps = DateComponents()
            comps.hour = plan.notifyHour
            comps.minute = plan.notifyMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: bedtimeId, content: content, trigger: trigger)
            try? await center.add(req)
            activeParts.append("Dormir \(plan.notifyLabel) → \(plan.bedtimeLabel)")
        }

        // 3. Real Wake-Up Alarm tied to SleepNeedDetailScreen's `smartAlarmEnabled`
        if smartAlarmEnabled {
            let winMin = min(max(settings.smartAlarmWindowMinutes, 0), 45)
            let winStartTotal = (((settings.smartAlarmHour * 60 + settings.smartAlarmMinute - winMin) % 1440) + 1440) % 1440
            let winStartLabel = String(format: "%02d:%02d", winStartTotal / 60, winStartTotal % 60)

            let content = UNMutableNotificationContent()
            content.title = "⏰ Buenos días · Despertar Improving (\(plan.wakeLabel))"
            content.subtitle = winMin > 0 ? "Ventana óptima \(winStartLabel)–\(plan.wakeLabel)" : "Objetivo de sueño \(plan.sleepNeedLabel)"
            content.body = "\(leadName)es tu hora objetivo de despertar. Sincroniza tu noche con «Sync Improving» para ver tu Recuperación y Batería Corporal."
            content.sound = .default

            var comps = DateComponents()
            comps.hour = min(max(settings.smartAlarmHour, 0), 23)
            comps.minute = min(max(settings.smartAlarmMinute, 0), 59)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: smartAlarmId, content: content, trigger: trigger)
            try? await center.add(req)
            activeParts.append("Alarma \(plan.wakeLabel)")
        }

        return "✓ Activos: " + activeParts.joined(separator: " · ")
    }

    func sendTestNotification(userName: String) async -> String {
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else {
            return "Activa el permiso en Ajustes de iOS → Notificaciones → Improving"
        }
        let cleanName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = UNMutableNotificationContent()
        content.title = "✓ Notificaciones de Improving activas"
        content.body = cleanName.isEmpty
            ? "Tus recordatorios de Diario, hora óptima de dormir y alarma inteligente funcionan correctamente."
            : "\(cleanName), tus avisos inteligentes de Diario, sueño y alarma están listos."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let req = UNNotificationRequest(identifier: testId, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
        return "✓ Enviada · Minimiza o bloquea el iPhone para verla en 3 s"
    }
}
