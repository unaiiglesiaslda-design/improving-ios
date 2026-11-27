import Foundation
import Combine
import SwiftUI
import UIKit
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

extension ImprovingStore {
    // MARK: - Apple Health & WHOOP Export Importer

    func importExportFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        importStatus = ExportImportStatus(
            isImporting: true,
            summaryMessage: "Leyendo exportación de Apple Health / WHOOP..."
        )
        let profileSnapshot = userProfile
        let priorSnapshot = realHistory
        Task.detached(priority: .userInitiated) {
            let result = WhoopExportImporter.importURLs(urls, profile: profileSnapshot, priorHistory: priorSnapshot)
            await MainActor.run {
                if let err = result.errorMessage, result.days.isEmpty {
                    self.importStatus = ExportImportStatus(isImporting: false, errorMessage: err)
                    return
                }
                self.applyImportedResult(result, navigateToLatest: true)
            }
        }
    }

    func applyImportedResult(_ result: ExportParseResult, navigateToLatest: Bool) {
        self.hasImportedOrPairedRealData = true
        self.clearPreviewSeededArtifactsOnRealData()
        var merged = WhoopExportImporter.mergeDays(existing: self.realHistory, imported: result.days)
        self.recomputeContinuousEnergy(in: &merged)
        self.realHistory = merged
        for (iso, map) in result.journalByDate {
            var dayJournal = self.journalCheckinsByDate[iso] ?? [:]
            for (k, v) in map { dayJournal[k] = v }
            self.journalCheckinsByDate[iso] = dayJournal
        }
        if navigateToLatest {
            if let latestIso = result.latestDateIso, let latestDate = self.isoFormatter.date(from: latestIso) {
                self.selectDate(latestDate)
            } else {
                self.dayOffset = 0
            }
        }
        let rangeText = (result.earliestDateIso != nil && result.latestDateIso != nil)
            ? "\(result.earliestDateIso!) – \(result.latestDateIso!)"
            : ""
        let hrvDaysCount = result.days.values.filter { $0.hrvMs != nil }.count
        var summary = "✓ \(result.days.count) días reales importados"
        if hrvDaysCount > 0 { summary += " · \(hrvDaysCount) días VFC" }
        if result.workoutsCount > 0 { summary += " · \(result.workoutsCount) entrenamientos" }
        self.importStatus = ExportImportStatus(
            isImporting: false,
            importedDaysCount: result.days.count,
            importedWorkoutsCount: result.workoutsCount,
            dateRangeLabel: rangeText,
            summaryMessage: summary,
            errorMessage: nil
        )
        self.dataRevision += 1
        self.persistState()
        self.publishWidgetSnapshot(triggerReload: true, forceReload: true)
        self.refreshSmartNotificationSchedules(promptPermission: false)
    }

    // MARK: - Zero-Entitlement Automatic Sync Bridge (Apple Shortcuts x-callback-url + Files Watcher + Top Floating Bubble)

    /// Builds Apple's official `shortcuts://x-callback-url/run-shortcut` URL so Shortcuts runs the user's sync shortcut
    /// and automatically returns straight back into Improving (`improving://sync?from=shortcut_ok`).
    static func buildShortcutCallbackURL(shortcutName: String) -> URL? {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "x-callback-url"
        comps.path = "/run-shortcut"
        comps.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "x-success", value: "improving://sync?from=shortcut_ok"),
            URLQueryItem(name: "x-cancel", value: "improving://sync?from=shortcut_cancel"),
            URLQueryItem(name: "x-error", value: "improving://sync?from=shortcut_error")
        ]
        return comps.url
    }

    func updateShortcutSyncConfig(name: String, autoRunOnOpen: Bool) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        shortcutSyncName = cleaned.isEmpty ? "Sync Improving" : cleaned
        autoRunShortcutOnOpen = autoRunOnOpen
        persistState()
    }

    func presentSyncBanner(_ state: SyncBannerState, autoDismissAfter seconds: Double? = nil) {
        syncBannerDismissTask?.cancel()
        withAnimation(.spring(response: 0.44, dampingFraction: 0.80)) {
            syncBannerState = state
        }
        if let seconds {
            syncBannerDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    self.syncBannerState = .hidden
                }
            }
        }
    }

    /// Deliberate deep pull-to-refresh on `HoyScreen` (>= 135 pt pull):
    /// Quietly runs the user's sync shortcut (if configured) or refreshes inbox/HealthKit WITHOUT vibrating!
    func handlePullToRefresh() async {
        if autoRunShortcutOnOpen {
            triggerShortcutRefreshSync(userInitiated: true)
            try? await Task.sleep(nanoseconds: 350_000_000)
            return
        }
        presentSyncBanner(.syncing("Sincronizando…"))
        scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
        #if os(iOS)
        if healthKitAuthorized && !healthKitSyncing {
            connectAndSyncAppleHealth()
        }
        #endif
        try? await Task.sleep(nanoseconds: 550_000_000)
    }

    /// Called whenever the app becomes `.active`.
    /// Strict anti-reload & zero-vibration policy: ONLY handles midnight calendar rollover and explicit return
    /// from a user-triggered Shortcut. Never reloads, flashes banners, or vibrates on normal app switching!
    func handleAppBecameActive() {
        refreshBackgroundRestTimer()
        // Refresh calendar day rollover so overnight suspended apps immediately show Today + reschedule smart alerts!
        let todayIso = isoFormatter.string(from: Date())
        let dayChanged = !lastActiveCalendarDayIso.isEmpty && lastActiveCalendarDayIso != todayIso
        if dayChanged {
            dataRevision += 1
            refreshSmartNotificationSchedules(promptPermission: false)
        }
        lastActiveCalendarDayIso = todayIso

        // Clear any pending shortcut state when returning without x-callback; NEVER read UIPasteboard here.
        if awaitingShortcutCallback {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
        }
        // Always perform a silent, zero-banner inbox check so background Shortcuts / Files drops load immediately!
        scanAutoSyncInboxIfNeeded(force: false, showBanner: false)
    }

    func scheduleSilentAutomationRechecks() {
        // Disabled background polling loops to keep the app calm, battery-friendly, and free of constant reloads.
        backgroundRecheckTask?.cancel()
    }

    /// Launches the user's Apple Shortcut via `shortcuts://x-callback-url/run-shortcut`, shows the floating
    /// `"Sincronizando…"` bubble above the date, and automatically reloads + updates all metrics on return.
    @discardableResult
    func triggerShortcutRefreshSync(userInitiated: Bool) -> Bool {
        if !userInitiated, let last = lastShortcutTriggerAt, Date().timeIntervalSince(last) < 90.0 {
            return false
        }

        guard let url = Self.buildShortcutCallbackURL(shortcutName: shortcutSyncName) else {
            scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
            return false
        }

        lastShortcutTriggerAt = Date()
        awaitingShortcutCallback = true
        autoSyncStatusText = "Ejecutando atajo «\(shortcutSyncName)»…"
        presentSyncBanner(.syncing("Sincronizando…"))

        // Safety timeout: never let the floating bubble stay stuck if user switches away from Shortcuts
        shortcutTimeoutTask?.cancel()
        shortcutTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 22_000_000_000)
            guard !Task.isCancelled, let self, self.awaitingShortcutCallback else { return }
            self.awaitingShortcutCallback = false
            self.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
        }

        #if os(iOS)
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !opened {
                    self.awaitingShortcutCallback = false
                    self.shortcutTimeoutTask?.cancel()
                    self.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
                }
            }
        }
        return true
        #else
        return false
        #endif
    }

    func scheduleDebouncedInboxScanFromWatcher() {
        inboxDebounceTask?.cancel()
        inboxDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, let self else { return }
            self.attachDirectSyncFileWatchers()
            self.scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
        }
    }

    func recordProcessedAutoSyncSignatures(_ sigs: [String]) {
        for s in sigs {
            if processedAutoSyncSignatures.insert(s).inserted {
                processedAutoSyncSignaturesOrder.append(s)
            }
        }
        if processedAutoSyncSignaturesOrder.count > 80 {
            let overflow = processedAutoSyncSignaturesOrder.count - 80
            let evicted = processedAutoSyncSignaturesOrder.prefix(overflow)
            processedAutoSyncSignaturesOrder.removeFirst(overflow)
            for old in evicted {
                processedAutoSyncSignatures.remove(old)
            }
        }
    }

    /// Synchronous background inbox processor used by `SyncAppleHealthShortcutIntent` & `BGAppRefreshTask`
    /// so automations parse, save protected JSON, and update WidgetKit even when Improving is closed!
    @discardableResult
    func processPendingInboxSyncNow() -> Int {
        let files = ShortcutsHealthSyncImporter.discoverInboxFiles()
        let pending: [(URL, String)] = files.compactMap { url in
            let sig = ShortcutsHealthSyncImporter.fileSignature(for: url)
            return processedAutoSyncSignatures.contains(sig) ? nil : (url, sig)
        }
        guard !pending.isEmpty else { return 0 }
        let result = WhoopExportImporter.importURLs(
            pending.map(\.0),
            profile: userProfile,
            priorHistory: realHistory
        )
        guard !result.days.isEmpty else { return 0 }
        recordProcessedAutoSyncSignatures(pending.map(\.1))
        // Clean ephemeral `shortcuts_latest.json` envelope after durable ingestion so stale payloads don't linger
        let latestEnvPath = ShortcutsHealthSyncImporter.latestShortcutsEnvelopeURL.standardizedFileURL.path
        if pending.contains(where: { $0.0.standardizedFileURL.path == latestEnvPath }) {
            try? FileManager.default.removeItem(at: ShortcutsHealthSyncImporter.latestShortcutsEnvelopeURL)
        }
        applyImportedResult(result, navigateToLatest: false)
        let hhmm = Self.currentHHMM()
        let newest = pending.last?.0.lastPathComponent ?? "Atajos"
        autoSyncStatusText = "✓ Sync \(hhmm) (\(newest)) · \(result.days.count)d\(Self.formatLatestReadingTag(from: result.days))"
        persistState(immediate: true)
        publishWidgetSnapshot(triggerReload: true, forceReload: false)
        return result.days.count
    }

    /// Live filesystem watchers on BOTH `En mi iPhone / Improving` and `AutoSync` directories PLUS direct
    /// file-level vnode watchers on `health_sync.json` & `shortcuts_latest.json` so in-place APFS overwrites
    /// from Apple Shortcuts trigger an immediate reload!
    func startInboxDirectoryWatcher() {
        func makeDirWatcher(for dirURL: URL) -> DispatchSourceFileSystemObject? {
            let fd = open(dirURL.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleDebouncedInboxScanFromWatcher()
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            return source
        }
        inboxDirectorySource = makeDirWatcher(for: ShortcutsHealthSyncImporter.publicDocumentsURL)
        autoSyncSubdirSource = makeDirWatcher(for: ShortcutsHealthSyncImporter.autoSyncInboxURL)
        attachDirectSyncFileWatchers()
    }

    func attachDirectSyncFileWatchers() {
        func makeFileWatcher(for fileURL: URL) -> DispatchSourceFileSystemObject? {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let fd = open(fileURL.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleDebouncedInboxScanFromWatcher()
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            return source
        }

        let healthSyncURL = ShortcutsHealthSyncImporter.publicDocumentsURL.appendingPathComponent("health_sync.json")
        healthSyncFileSource?.cancel()
        healthSyncFileSource = makeFileWatcher(for: healthSyncURL)

        let latestEnvURL = ShortcutsHealthSyncImporter.latestShortcutsEnvelopeURL
        shortcutsLatestFileSource?.cancel()
        shortcutsLatestFileSource = makeFileWatcher(for: latestEnvURL)
    }

    func scanAutoSyncInboxIfNeeded(force: Bool = false, showBanner: Bool = false) {
        // Never silently drop a fresh sync event while another scan is still running: queue it!
        if isAutoSyncing {
            let prev = pendingInboxRescan
            pendingInboxRescan = (force: (prev?.force ?? false) || force, showBanner: (prev?.showBanner ?? false) || showBanner)
            return
        }
        let files = ShortcutsHealthSyncImporter.discoverInboxFiles()
        let pending: [(URL, String)] = files.compactMap { url in
            let sig = ShortcutsHealthSyncImporter.fileSignature(for: url)
            let alreadySeen = processedAutoSyncSignatures.contains(sig)
            if !force && alreadySeen { return nil }
            // On forced refresh (pull-to-refresh / shortcut callback), avoid re-parsing multi-MB exportar.zip archives whose signature didn't change!
            if force && alreadySeen && !ShortcutsHealthSyncImporter.isLightweightAutoSyncFile(url: url) {
                return nil
            }
            return (url, sig)
        }
        guard !pending.isEmpty else {
            if force {
                let hhmm = Self.currentHHMM()
                autoSyncStatusText = "Revisado a las \(hhmm) · Sin archivos nuevos en Atajos/Carpeta"
                if showBanner {
                    presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 1.8)
                }
            }
            return
        }

        isAutoSyncing = true
        autoSyncStatusText = "Sincronizando desde Atajos / Carpeta..."
        if showBanner || syncBannerState != .hidden {
            presentSyncBanner(.syncing("Sincronizando…"))
        }
        let profileSnapshot = userProfile
        let priorSnapshot = realHistory
        let pendingURLs = pending.map(\.0)
        let pendingSigs = pending.map(\.1)
        let newestFileName = pendingURLs.last?.lastPathComponent ?? "Atajos"

        Task.detached(priority: .userInitiated) {
            let result = WhoopExportImporter.importURLs(pendingURLs, profile: profileSnapshot, priorHistory: priorSnapshot)
            await MainActor.run {
                self.isAutoSyncing = false
                if !result.days.isEmpty {
                    // Only mark signatures as processed AFTER a valid parse so partial mid-write reads are NEVER blacklisted!
                    self.recordProcessedAutoSyncSignatures(pendingSigs)
                    let latestEnvPath = ShortcutsHealthSyncImporter.latestShortcutsEnvelopeURL.standardizedFileURL.path
                    if pendingURLs.contains(where: { $0.standardizedFileURL.path == latestEnvPath }) {
                        try? FileManager.default.removeItem(at: ShortcutsHealthSyncImporter.latestShortcutsEnvelopeURL)
                    }
                    let shouldJump = !self.hasImportedOrPairedRealData
                    self.applyImportedResult(result, navigateToLatest: shouldJump)
                    let hhmm = Self.currentHHMM()
                    let latestReading = Self.formatLatestReadingTag(from: result.days)
                    self.autoSyncStatusText = "✓ Sync \(hhmm) (\(newestFileName)) · \(result.days.count)d\(latestReading)"
                    self.persistState()
                    if showBanner || self.syncBannerState != .hidden {
                        self.presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 2.1)
                    }
                } else {
                    if force {
                        self.autoSyncStatusText = result.errorMessage ?? "Archivo detectado sin muestras válidas (\(newestFileName))"
                    }
                    if showBanner || self.syncBannerState != .hidden {
                        self.presentSyncBanner(.hidden)
                    }
                    // Retry once after 1.1s in case Apple Shortcuts was still flushing `health_sync.json`!
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_100_000_000)
                        self?.scanAutoSyncInboxIfNeeded(force: false, showBanner: showBanner)
                    }
                }

                // Drain any queued rescan that arrived while this sync was running!
                if let queued = self.pendingInboxRescan {
                    self.pendingInboxRescan = nil
                    self.scanAutoSyncInboxIfNeeded(force: queued.force, showBanner: queued.showBanner)
                }
            }
        }
    }

    static func formatLatestReadingTag(from days: [String: RealBiometricDaySummary]) -> String {
        guard let latestIso = days.keys.max(), let d = days[latestIso] else { return "" }
        let shortDay: String = {
            guard let dt = AppFormatters.parseIsoDay(latestIso) else { return latestIso }
            return AppFormatters.dMMM.string(from: dt).replacingOccurrences(of: ".", with: "")
        }()
        if let lastMin = d.stressSamples5m.last?.minuteOfDay {
            let timeStr = String(format: "%02d:%02d", (lastMin / 60) % 24, lastMin % 60)
            return " · Últ. FC \(shortDay) \(timeStr)"
        }
        return " · Hasta \(shortDay)"
    }

    func handleDeepLinkRoute(_ route: String) {
        let key = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dest: DeepLinkRequest.Destination
        switch key {
        case "diario", "journal":
            dest = .diario
        case "sleep", "sueno", "sueño":
            dest = .sueno
        case "nutrition", "nutricion", "nutrición", "food":
            dest = .nutricion
        case "esfuerzo", "strain":
            dest = .esfuerzo
        case "fitness", "workout", "entrenamiento":
            dest = .fitness
        case "biologia", "biología", "biology":
            dest = .biologia
        case "settings", "dispositivos", "ajustes":
            dest = .dispositivos
        case "ask", "coach", "askbevel":
            dest = .askBevel
        default:
            dest = .hoy
        }
        pendingDeepLinkRoute = DeepLinkRequest(destination: dest)
    }

    func handleIncomingURL(_ url: URL) {
        // 1. File opened via Share Sheet / Files app ("Abrir en Improving")
        if url.isFileURL {
            importExportFiles(urls: [url])
            return
        }

        // 2. Custom URL Scheme: improving://<route> or improving://sync[?from=shortcut_ok | ?source=clipboard | ?data=... | ?payload=...]
        guard url.scheme?.lowercased() == "improving" else { return }
        let host = (url.host ?? "").lowercased()
        if host == "open" {
            publishWidgetSnapshot(triggerReload: true, forceReload: false)
            return
        }
        if ["hoy", "home", "diario", "journal", "sleep", "sueno", "nutrition", "nutricion", "esfuerzo", "strain", "fitness", "biologia", "biology", "settings", "dispositivos"].contains(host) {
            handleDeepLinkRoute(host)
            return
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let fromParam = items.first(where: { $0.name.lowercased() == "from" })?.value?.lowercased()
        let sourceParam = items.first(where: { $0.name.lowercased() == "source" })?.value?.lowercased()
        let rawParam = items.first(where: { $0.name.lowercased() == "data" || $0.name.lowercased() == "payload" || $0.name.lowercased() == "text" })?.value

        // Clear pending shortcut callback & refresh anti-loop timestamp immediately!
        if let from = fromParam, from.hasPrefix("shortcut") {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
            lastShortcutTriggerAt = Date()

            if from == "shortcut_cancel" {
                autoSyncStatusText = "Sincronización cancelada"
                presentSyncBanner(.hidden)
                return
            }
            if from == "shortcut_error" {
                autoSyncStatusText = "No se pudo ejecutar «\(shortcutSyncName)» · Revisa el nombre en Dispositivos"
                presentSyncBanner(.notice("Revisa nombre del atajo"), autoDismissAfter: 2.6)
                return
            }
            // from == "shortcut_ok": scan inbox only (direct URL payload arrives via ?data= without touching Pasteboard!)
            scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
            return
        }

        if sourceParam == "clipboard" {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
            presentSyncBanner(.syncing("Sincronizando…"))
            let paste = UIPasteboard.general.string ?? ""
            ingestRawShortcutsPayload(paste, sourceLabel: "Sync Improving")
            return
        }

        if let raw = rawParam, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
            presentSyncBanner(.syncing("Sincronizando…"))
            let decoded: String = {
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    return raw
                }
                let plusFixed = raw.replacingOccurrences(of: "+", with: " ")
                if let pct = plusFixed.removingPercentEncoding, pct.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    return pct
                }
                if let b64 = Data(base64Encoded: raw), let str = String(data: b64, encoding: .utf8), !str.isEmpty {
                    return str
                }
                return raw
            }()
            ingestRawShortcutsPayload(decoded, sourceLabel: "Sync Improving")
            return
        }

        // Default: scan `En mi iPhone / Improving` & `AutoSync` inbox immediately!
        scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
    }

    func ingestRawShortcutsPayload(_ text: String, sourceLabel: String = "Atajos de Apple") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            autoSyncStatusText = "No había datos de Salud en \(sourceLabel)"
            presentSyncBanner(.hidden)
            return
        }
        // Dedupe back-to-back callback + clipboard URL delivery of the exact same payload within 4s
        let payloadHash = trimmed.hashValue
        if let prevHash = lastIngestedPayloadHash, let prevAt = lastIngestedPayloadAt,
           prevHash == payloadHash, Date().timeIntervalSince(prevAt) < 4.0 {
            presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 1.8)
            return
        }
        lastIngestedPayloadHash = payloadHash
        lastIngestedPayloadAt = Date()
        isAutoSyncing = true
        autoSyncStatusText = "Procesando \(sourceLabel)..."
        presentSyncBanner(.syncing("Sincronizando…"))
        let profileSnapshot = userProfile
        let priorSnapshot = realHistory

        Task.detached(priority: .userInitiated) {
            let result = ShortcutsHealthSyncImporter.parseRawText(
                trimmed,
                sourceName: sourceLabel,
                profile: profileSnapshot,
                priorHistory: priorSnapshot
            )
            await MainActor.run {
                self.isAutoSyncing = false
                if !result.days.isEmpty {
                    let shouldJump = !self.hasImportedOrPairedRealData
                    self.applyImportedResult(result, navigateToLatest: shouldJump)
                    let hhmm = Self.currentHHMM()
                    let latestReading = Self.formatLatestReadingTag(from: result.days)
                    self.autoSyncStatusText = "✓ \(sourceLabel) \(hhmm) · \(result.days.count)d\(latestReading)"
                    self.persistState()
                    self.presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 2.1)
                } else {
                    self.autoSyncStatusText = result.errorMessage ?? "Sin lecturas válidas en \(sourceLabel)"
                    self.presentSyncBanner(.hidden)
                }
            }
        }
    }

    static func currentHHMM() -> String {
        AppFormatters.hhmmString(from: Date())
    }

    // MARK: - HealthKit & WHOOP Live Connectors (Full 60-Day Bevel Pipeline + Continuous Energy!)

    func connectAndSyncAppleHealth() {
        #if os(iOS)
        healthKitSyncing = true
        healthKitLastSyncText = "Conectando..."
        Task {
            do {
                try await HealthKitReader.shared.requestAuthorization()
                self.healthKitAuthorized = HealthKitReader.shared.isAuthorized
                if self.healthKitAuthorized {
                    self.healthKitPreviouslyAuthorized = true
                    self.persistState()
                }
                self.healthKitLastSyncText = "Sincronizando 60 días..."
                HealthKitReader.shared.configuredAgeYears = Int(self.userProfile.effectiveAgeYears.rounded())
                HealthKitReader.shared.configuredRestingHrBpm = self.restingHrBpm > 30 ? self.restingHrBpm : 55.0
                let historySnaps = await HealthKitReader.shared.syncHistoryDays(days: 60)
                self.ingestHealthKitSnapshots(historySnaps)
                let realDays = self.realHistory.count
                let hrvDays = self.realHistory.values.filter { $0.hrvMs != nil }.count
                self.healthKitLastSyncText = "Sincronizado (\(realDays)d · \(hrvDays) VFC)"
            } catch {
                self.healthKitLastSyncText = error.localizedDescription
            }
            self.healthKitSyncing = false
        }
        #endif
    }

    func bindHealthKit() {
        #if os(iOS)
        HealthKitReader.shared.$latestSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                guard let self, let snap else { return }
                self.ingestHealthKitSnapshots([snap])
            }
            .store(in: &cancellables)
        #endif
    }

    #if os(iOS)
    func ingestHealthKitSnapshots(_ snapshots: [DailyHealthSnapshot]) {
        guard !snapshots.isEmpty else { return }
        let sorted = snapshots.sorted { $0.day < $1.day }
        let cal = Calendar.current
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let maxHr = Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: userProfile))
        let popLnHrv = log(max(norms.hrvExpectedMs, 15.0))
        let popRhr = norms.restingHrExpected
        let popResp = (norms.respLowRpm + norms.respHighRpm) / 2.0

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "HH:mm"
        let fullFmt = DateFormatter()
        fullFmt.locale = Locale(identifier: "es_ES")
        fullFmt.dateFormat = "dd/MM/yy 'a las' H:mm"

        // Seed causal baselines from any existing realHistory strictly BEFORE the first synced snapshot
        // Keep RMSSD and SDNN pools strictly separated so HRV method changes never distort the 60d baseline!
        let firstIso = isoFormatter.string(from: sorted[0].day)
        var priorLnHrvRmssd: [Double] = []
        var priorLnHrvSdnn: [Double] = []
        var priorRhr: [Double] = []
        var priorResp: [Double] = []
        var priorTemp: [Double] = []
        var prevDayEndEnergy: Double? = nil
        var prevDayIso: String? = nil

        for iso in realHistory.keys.sorted() where iso < firstIso {
            if let old = realHistory[iso] {
                if let h = old.hrvMs, h > 2 {
                    if old.hrvMethodLabel?.uppercased().contains("SDNN") == true {
                        priorLnHrvSdnn.append(log(h))
                    } else {
                        priorLnHrvRmssd.append(log(h))
                    }
                }
                if let r = old.restingHrBpm { priorRhr.append(r) }
                if let rr = old.respRateRpm { priorResp.append(rr) }
                if let t = old.wristTempAbsoluteC { priorTemp.append(t) }
                if let lastE = old.energySamples5m.last?.value ?? old.energyBankPercent.map({ Double($0) }) {
                    prevDayEndEnergy = lastE
                    prevDayIso = iso
                }
            }
        }

        var updatedAny = false

        for snap in sorted {
            let iso = isoFormatter.string(from: snap.day)
            var d = realHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
            var hasReal = false

            // 1. Sleeping HRV (Bevel/WHOOP beat-to-beat RMSSD over Entire Sleep, with clean fallback!)
            if snap.hrv.sampleCount > 0 && snap.hrv.weightedHRV > 2.0 {
                d.hrvMs = AppleHealthExportImporter.round1(snap.hrv.weightedHRV)
                d.hrvMethodLabel = snap.hrv.method
                hasReal = true
            }

            // 2. Sleeping RHR (prefer sleeping mean HR when measured, fallback Apple Resting HR)
            if snap.heartRate.sleepingMeanHR > 25.0 {
                d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.sleepingMeanHR)
                hasReal = true
            } else if snap.heartRate.restingHR > 25.0 {
                d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.restingHR)
                hasReal = true
            }

            // 3. Daytime HR (strictly outside sleep window)
            if let live = snap.liveHeartRate, live > 28.0 {
                d.liveHrBpm = Int(live.rounded())
                hasReal = true
            }

            // 4. Vitals (strictly optional — zero fake 14.5 / 98.0 defaults!)
            if let resp = snap.vitals.meanRespiratoryRate, resp > 5.0 {
                d.respRateRpm = AppleHealthExportImporter.round1(resp)
                hasReal = true
            }
            if let spo2 = snap.vitals.meanSpO2, spo2 >= 60.0 {
                d.spo2Percent = AppleHealthExportImporter.round1(spo2)
                hasReal = true
            }
            if let tAbs = snap.vitals.tempAbsoluteCelsius {
                d.wristTempAbsoluteC = AppleHealthExportImporter.round1(tAbs)
                let tBase = priorTemp.isEmpty ? tAbs : (priorTemp.suffix(30).reduce(0, +) / Double(min(priorTemp.count, 30)))
                d.wristTempDeltaC = AppleHealthExportImporter.round1(tAbs - tBase)
                hasReal = true
            } else if let tDelta = snap.vitals.tempDeltaCelsius {
                d.wristTempDeltaC = AppleHealthExportImporter.round1(tDelta)
                hasReal = true
            }

            // 5. Sleep session + hypnogram stages + overnight vitals + Bevel Sleep Score
            var sleepStartEp: Int64? = nil
            var sleepEndEp: Int64? = nil
            if let sl = snap.sleep, sl.totalAsleepMinutes > 0 {
                let asleepMin = Int(sl.totalAsleepMinutes.rounded())
                let inBedMin = Int(sl.inBedMinutes.rounded())
                let deepMin = sl.deepMinutes > 0 ? Int(sl.deepMinutes.rounded()) : nil
                let remMin = sl.remMinutes > 0 ? Int(sl.remMinutes.rounded()) : nil
                let coreMin = sl.coreMinutes > 0 ? Int(sl.coreMinutes.rounded()) : nil
                let awakeMin = sl.awakeMinutes > 0 ? Int(sl.awakeMinutes.rounded()) : nil

                sleepStartEp = Int64(sl.startDate.timeIntervalSince1970)
                sleepEndEp = Int64(sl.endDate.timeIntervalSince1970)

                let awakeBlocks = sl.stages.filter { $0.stageCode == 0 }.count
                let continuityPct: Int? = awakeBlocks > 0
                    ? max(20, min(100, 100 - awakeBlocks * 7 - Int((sl.awakeMinutes) * 0.8)))
                    : nil

                let hrDipPct: Double? = {
                    guard let dayHr = d.liveHrBpm, dayHr > 0, snap.heartRate.sleepingMeanHR > 25 else { return nil }
                    return AppleHealthExportImporter.round1(max(-10.0, min(40.0, (Double(dayHr) - snap.heartRate.sleepingMeanHR) / Double(dayHr) * 100.0)))
                }()

                let stageBlocks: [SleepStageBlock] = sl.stages.enumerated().map { idx, st in
                    let kind: SleepStageKind = switch st.stageCode {
                    case 0: .awake
                    case 1: .rem
                    case 3: .deep
                    default: .core
                    }
                    return SleepStageBlock(
                        id: "hk_st_\(iso)_\(idx)",
                        stage: kind,
                        startEpochSec: Int64(st.startDate.timeIntervalSince1970),
                        endEpochSec: Int64(st.endDate.timeIntervalSince1970)
                    )
                }

                let toTimed: ([TimedHealthSample]) -> [TimedBiometricPoint] = { arr in
                    arr.map { s in
                        let c = cal.dateComponents([.hour, .minute], from: s.date)
                        let mod = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                        return TimedBiometricPoint(
                            minuteOfDay: mod,
                            value: AppleHealthExportImporter.round1(s.value),
                            epochSec: Int64(s.date.timeIntervalSince1970)
                        )
                    }
                }

                d.asleepMinutes = asleepMin
                d.inBedMinutes = inBedMin
                d.deepMinutes = deepMin
                d.remMinutes = remMin
                d.coreMinutes = coreMin
                d.awakeMinutes = awakeMin
                d.sleepDebtMinutes = max(Int((norms.sleepTargetHours * 60.0).rounded()) - asleepMin, 0)
                d.sleepPct = WhoopPhysiologyEngine.computeBevelSleepScore(
                    asleepMinutes: asleepMin,
                    inBedMinutes: inBedMin > 0 ? inBedMin : nil,
                    deepMinutes: deepMin,
                    remMinutes: remMin,
                    awakeMinutes: awakeMin,
                    awakeCount: awakeBlocks,
                    hrDipPct: hrDipPct,
                    targetMinutes: norms.sleepTargetHours * 60.0,
                    deepTargetPct: norms.deepTargetPct,
                    remTargetPct: norms.remTargetPct
                )
                d.sleepSession = SleepSessionDetail(
                    startEpochSec: sleepStartEp,
                    endEpochSec: sleepEndEp,
                    startTimeLabel: timeFmt.string(from: sl.startDate),
                    endTimeLabel: timeFmt.string(from: sl.endDate),
                    startDateTimeLabel: fullFmt.string(from: sl.startDate),
                    sourceName: sl.sourceName,
                    awakeSeconds: awakeMin.map { $0 * 60 },
                    remSeconds: remMin.map { $0 * 60 },
                    coreSeconds: coreMin.map { $0 * 60 },
                    deepSeconds: deepMin.map { $0 * 60 },
                    latencyMinutes: sl.latencyMinutes,
                    efficiencyPct: Int(sl.efficiencyPct.rounded()),
                    hrDipPct: hrDipPct,
                    continuityPct: continuityPct,
                    stages: stageBlocks,
                    sleepHrSamples: toTimed(snap.sleepHrSamples),
                    sleepHrvSamples: toTimed(snap.sleepHrvSamples),
                    sleepRespSamples: toTimed(snap.sleepRespSamples),
                    sleepSpo2Samples: toTimed(snap.sleepSpo2Samples)
                )
                hasReal = true
            }

            // 6. Activity, Workouts, HR Zones & Bevel Strain
            if let steps = snap.steps { d.stepsCount = steps; hasReal = true }
            if let kcal = snap.activeCalories { d.activeKcal = Int(kcal.rounded()); hasReal = true }
            if let basal = snap.basalCalories, basal > 100 { d.basalKcal = Int(basal.rounded()); hasReal = true }
            if let v = snap.vo2Max { d.vo2MaxMlKgMin = AppleHealthExportImporter.round1(v); hasReal = true }
            if let hrr = snap.hrRecoveryBpm { d.hrRecoveryBpm = AppleHealthExportImporter.round1(hrr); hasReal = true }
            if let w = snap.bodyWeightKg { d.bodyWeightKg = AppleHealthExportImporter.round1(w); hasReal = true }
            if let f = snap.bodyFatPct { d.bodyFatPct = AppleHealthExportImporter.round1(f); hasReal = true }
            if let l = snap.leanMassKg { d.leanMassKg = AppleHealthExportImporter.round1(l); hasReal = true }
            if let s = snap.systolicBp { d.systolicBp = s; hasReal = true }
            if let dia = snap.diastolicBp { d.diastolicBp = dia; hasReal = true }
            if let dl = snap.daylightMinutes { d.daylightMinutes = dl; hasReal = true }
            if let noise = snap.sleepNoiseOver50Db { d.sleepNoiseOver50Db = noise; hasReal = true }

            let dayIsSdnn = (d.hrvMethodLabel?.uppercased().contains("SDNN") == true)
            let hrvPopMean = dayIsSdnn ? log(max(norms.hrvExpectedMs * 1.18, 15.0)) : popLnHrv
            let rhrBaseline = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorRhr,
                populationMean: popRhr,
                populationSigma: WhoopPhysiologyEngine.baselinePopulationRhrSigma,
                floorSigma: WhoopPhysiologyEngine.baselineFloorRhrSigma
            )
            let lnHrvBaseline = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: dayIsSdnn ? priorLnHrvSdnn : priorLnHrvRmssd,
                populationMean: hrvPopMean,
                populationSigma: WhoopPhysiologyEngine.baselinePopulationHrvSigma,
                floorSigma: WhoopPhysiologyEngine.baselineFloorHrvSigma
            )
            let respBaseline = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorResp,
                populationMean: popResp,
                populationSigma: WhoopPhysiologyEngine.baselinePopulationRespSigma,
                floorSigma: WhoopPhysiologyEngine.baselineFloorRespSigma
            )
            let rhrRef = d.restingHrBpm ?? rhrBaseline.mean

            var workoutSpans: [ClosedRange<Int64>] = []
            if !snap.workouts.isEmpty {
                let importedWorkouts: [EffortEventItem] = snap.workouts.map { w in
                    let sEp = Int64(w.startDate.timeIntervalSince1970)
                    let eEp = max(Int64(w.endDate.timeIntervalSince1970), sEp + Int64(w.durationMinutes * 60))
                    workoutSpans.append(sEp...eEp)
                    let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
                        durationMin: w.durationMinutes,
                        kcal: w.activeCalories,
                        avgHrBpm: w.avgHeartRate,
                        rhrBpm: rhrRef,
                        maxHrBpm: maxHr,
                        banisterB: userProfile.sex.banisterB
                    )
                    return EffortEventItem(
                        id: w.id.uuidString,
                        title: w.name,
                        timeRange: "\(timeFmt.string(from: w.startDate)) - \(timeFmt.string(from: w.endDate))",
                        durationMin: w.durationMinutes,
                        avgHrBpm: w.avgHeartRate,
                        strainScore: ws.strain21,
                        strainPct: ws.strainPct,
                        categoryLabel: w.isStrength ? "Fuerza" : "Cardio",
                        kcal: w.activeCalories,
                        dateIso: iso,
                        startEpochSec: sEp
                    )
                }
                // Merge HealthKit workouts while preserving manual strength sessions & AI-logged workouts!
                var mergedWorkouts = importedWorkouts
                for existingW in d.workouts {
                    if let dupIdx = mergedWorkouts.firstIndex(where: { WhoopExportImporter.workoutsOverlapOrMatch($0, existingW) }) {
                        if existingW.totalSets != nil && mergedWorkouts[dupIdx].totalSets == nil {
                            mergedWorkouts[dupIdx] = existingW
                        }
                    } else {
                        mergedWorkouts.append(existingW)
                        if let sEp = existingW.startEpochSec {
                            workoutSpans.append(sEp...(sEp + Int64(max(existingW.durationMin, 1) * 60)))
                        }
                    }
                }
                d.workouts = mergedWorkouts
                d.strengthMinutes = mergedWorkouts.filter { $0.categoryLabel == "Fuerza" }.reduce(0) { $0 + $1.durationMin }
                hasReal = true
            }

            if !snap.intradayHrSamples.isEmpty {
                let hrTuples: [(Int64, Int, Double)] = snap.intradayHrSamples.map { s in
                    let ep = Int64(s.date.timeIntervalSince1970)
                    let c = cal.dateComponents([.hour, .minute], from: s.date)
                    return (ep, (c.hour ?? 0) * 60 + (c.minute ?? 0), s.value)
                }
                d.hrZoneMinutes = AppleHealthExportImporter.computeHrZoneMinutes(
                    samples: hrTuples.map { ($0.0, $0.2) },
                    workoutSpans: workoutSpans,
                    maxHr: maxHr,
                    rhr: rhrRef
                )
                hasReal = true
            }

            // 7. Bevel Adaptive Recovery % (strictly requires recorded sleep for the day — never show recovery without sleep!)
            let hasSleepForRecovery = d.hasRecordedSleep
            d.recoveryPct = hasSleepForRecovery ? WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                hrvMs: d.hrvMs,
                rhrBpm: d.restingHrBpm,
                respRpm: d.respRateRpm,
                spo2Pct: d.spo2Percent,
                wristTempDeltaC: d.wristTempDeltaC,
                lnHrvBaseline: lnHrvBaseline,
                rhrBaseline: rhrBaseline,
                respBaseline: respBaseline,
                profile: userProfile,
                sleepPct: d.sleepPct
            ) : nil

            // 8. Bevel Calibrated Strain
            if let strainPair = WhoopPhysiologyEngine.computeBevelStrain(
                profile: userProfile,
                rhrBpm: rhrRef,
                hrZoneMinutes: d.hrZoneMinutes,
                workouts: d.workouts,
                activeKcal: d.activeKcal.map { Double($0) }
            ) {
                d.strain21 = strainPair.strain21
                d.strainPct = strainPair.strainPct
                hasReal = true
            }

            // 9. 5-Minute Stress + CONTINUOUS Cross-Day Energy Bank (ZERO midnight jump + Low Power Mode sleep resilience!)
            var stress5m: [TimedBiometricPoint] = []
            if !snap.intradayHrSamples.isEmpty {
                let hrTuples: [(Int64, Int, Double)] = snap.intradayHrSamples.map { s in
                    let ep = Int64(s.date.timeIntervalSince1970)
                    let c = cal.dateComponents([.hour, .minute], from: s.date)
                    return (ep, (c.hour ?? 0) * 60 + (c.minute ?? 0), s.value)
                }
                let hrvFactor: Double = {
                    guard let h = d.hrvMs, h > 2 else { return 1.0 }
                    let ratio = exp(lnHrvBaseline.mean) / h
                    return min(max(ratio, 0.72), 1.40)
                }()
                stress5m = AppleHealthExportImporter.buildFiveMinuteStressSamples(
                    hrSamples: hrTuples,
                    rhrRef: rhrRef,
                    maxHr: maxHr,
                    hrvFactor: hrvFactor,
                    sleepStartEpoch: sleepStartEp,
                    sleepEndEpoch: sleepEndEp
                )
                if !stress5m.isEmpty {
                    d.stressSamples5m = stress5m
                    d.stressScore = Int((stress5m.map(\.value).reduce(0, +) / Double(stress5m.count)).rounded())
                    hasReal = true
                }
            }

            let hasRecordedSleepToday = (sleepStartEp != nil && sleepEndEp != nil) || ((d.asleepMinutes ?? 0) > 0)
            if !stress5m.isEmpty || hasRecordedSleepToday {
                let isConsecutiveDay: Bool = {
                    guard let prevIso = prevDayIso,
                          let prevDt = isoFormatter.date(from: prevIso),
                          let diff = cal.dateComponents([.day], from: prevDt, to: snap.day).day else { return false }
                    return diff == 1
                }()
                let startingEnergy: Double = {
                    if isConsecutiveDay, let carried = prevDayEndEnergy {
                        return carried
                    }
                    if hasRecordedSleepToday {
                        return Double(max(min((d.recoveryPct ?? d.sleepPct ?? 65) - 34, 48), 22))
                    }
                    return Double(d.recoveryPct ?? d.sleepPct ?? 58)
                }()

                let energy5m = AppleHealthExportImporter.buildContinuousFiveMinuteEnergySamples(
                    stressSamples: stress5m,
                    startingEnergy: startingEnergy,
                    recoveryPct: d.recoveryPct,
                    sleepPct: d.sleepPct,
                    sleepStartEpoch: sleepStartEp,
                    sleepEndEpoch: sleepEndEp,
                    workoutSpans: workoutSpans,
                    asleepMinutes: d.asleepMinutes,
                    dayStartEpoch: Int64(cal.startOfDay(for: snap.day).timeIntervalSince1970)
                )
                if let lastPt = energy5m.last {
                    d.energySamples5m = energy5m
                    d.energyBankPercent = Int(lastPt.value.rounded())
                    prevDayEndEnergy = lastPt.value
                    prevDayIso = iso
                    hasReal = true
                }
            }

            // Advance causal baselines AFTER computing today
            if let h = d.hrvMs, h > 2 {
                if dayIsSdnn { priorLnHrvSdnn.append(log(h)) } else { priorLnHrvRmssd.append(log(h)) }
            }
            if let r = d.restingHrBpm { priorRhr.append(r) }
            if let rr = d.respRateRpm { priorResp.append(rr) }
            if let t = d.wristTempAbsoluteC { priorTemp.append(t) }

            if hasReal {
                realHistory[iso] = d
                updatedAny = true
            }
        }

        if updatedAny {
            hasImportedOrPairedRealData = true
            clearPreviewSeededArtifactsOnRealData()
            healthKitAuthorized = true
            dataRevision += 1
            persistState()
        }
    }
    #endif

    func toggleWhoopScan() {
        if whoopScanning {
            whoopBleReader.stopScanning()
            whoopScanning = false
        } else {
            whoopScanning = true
            whoopBleReader.startScanning(for: nil)
        }
    }

    func disconnectWhoop() {
        whoopBleReader.disconnect()
        whoopConnected = false
        whoopScanning = false
    }

    func forceWhoopSync() {
        whoopBleReader.setRealtimeHR(enabled: true)
        whoopBleReader.requestHistoricalData()
    }

    func bindWhoopBle() {
        whoopBleReader.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] st in
                guard let self else { return }
                self.whoopConnected = (st == .ready)
                self.whoopScanning = (st == .scanning)
                if st == .ready {
                    self.whoopDeviceName = self.whoopBleReader.strapName ?? "WHOOP 5.0"
                }
            }
            .store(in: &cancellables)

        whoopBleReader.$latestBatteryPercent
            .receive(on: RunLoop.main)
            .sink { [weak self] pct in
                if let pct { self?.whoopBatteryPct = pct }
            }
            .store(in: &cancellables)

        let reader = whoopBleReader
        bleStreamTask = Task { [weak self] in
            for await reading in reader.readings {
                if Task.isCancelled { break }
                guard let self else { break }
                self.whoopPacketsReceived += 1
                switch reading {
                case .standardHeartRate(let bpm, let rrMs, _, let ts):
                    self.whoopLiveHrBpm = bpm
                    // Buffer clean RR intervals (300..2000 ms) without clobbering overnight sleeping HRV!
                    let validRr = rrMs.map(Double.init).filter { (300.0...2000.0).contains($0) }
                    if !validRr.isEmpty {
                        self.whoopPendingRrBuffer.append(contentsOf: validRr)
                        if self.whoopPendingRrBuffer.count > 120 {
                            self.whoopPendingRrBuffer.removeFirst(self.whoopPendingRrBuffer.count - 120)
                        }
                    }
                    // Throttle full `realHistory` dictionary mutations to once per 10 seconds to prevent 1 Hz UI redraw storms!
                    let now = Date()
                    let shouldCommit = self.lastWhoopHistoryCommitAt == nil || now.timeIntervalSince(self.lastWhoopHistoryCommitAt!) >= 10.0
                    if shouldCommit {
                        self.lastWhoopHistoryCommitAt = now
                        let iso = self.isoFormatter.string(from: ts)
                        var d = self.realHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
                        d.liveHrBpm = bpm
                        // Only seed HRV from live BLE RR if no overnight sleeping HRV exists yet AND >= 15 RR beats collected!
                        if d.hrvMs == nil && self.whoopPendingRrBuffer.count >= 15 {
                            var sqDiffs: [Double] = []
                            for i in 1..<self.whoopPendingRrBuffer.count {
                                let diff = self.whoopPendingRrBuffer[i] - self.whoopPendingRrBuffer[i - 1]
                                if abs(diff) <= 300.0 {
                                    sqDiffs.append(diff * diff)
                                }
                            }
                            if sqDiffs.count >= 10 {
                                let rmssd = sqrt(sqDiffs.reduce(0, +) / Double(sqDiffs.count))
                                if (8.0...220.0).contains(rmssd) {
                                    d.hrvMs = AppleHealthExportImporter.round1(rmssd)
                                    d.hrvMethodLabel = "RMSSD · WHOOP en vivo"
                                }
                            }
                        }
                        self.realHistory[iso] = d
                        if !self.hasImportedOrPairedRealData {
                            self.hasImportedOrPairedRealData = true
                            self.clearPreviewSeededArtifactsOnRealData()
                        }
                    }
                case .liveFrame(_, let streams):
                    if let lastHr = streams.hr.last, (28...235).contains(lastHr.bpm) {
                        self.whoopLiveHrBpm = lastHr.bpm
                    }
                case .historicalChunk(_, _, let endData, let streams):
                    self.ingestWhoopHistoricalChunk(streams: streams, endData: endData)
                case .historicalComplete:
                    self.bleLogs = (["✓ Descarga histórica WHOOP completada"] + self.bleLogs).prefix(20).map { $0 }
                case .battery(let pct, _, _, _):
                    self.whoopBatteryPct = pct
                case .log(let msg):
                    self.bleLogs = ([msg] + self.bleLogs).prefix(20).map { $0 }
                default:
                    break
                }
            }
        }
    }

    /// Persists a decoded WHOOP BLE historical chunk into `realHistory` and ONLY acknowledges
    /// `ackHistoricalChunk(endData:)` AFTER durable write completes so no strap records are ever lost!
    func ingestWhoopHistoricalChunk(streams: Streams, endData: [UInt8]) {
        guard !streams.hr.isEmpty || !streams.rr.isEmpty || !streams.resp.isEmpty || !streams.steps.isEmpty else {
            whoopBleReader.ackHistoricalChunk(endData: endData)
            return
        }
        var days: [String: AppleHealthExportImporter.MutableAppleDay] = [:]
        let cal = Calendar.current
        func dayFor(_ unixSec: Int) -> (AppleHealthExportImporter.MutableAppleDay, Int64, Int) {
            let dt = Date(timeIntervalSince1970: TimeInterval(unixSec))
            let iso = AppFormatters.isoDayString(from: dt, calendar: cal)
            let comps = cal.dateComponents([.hour, .minute], from: dt)
            let mod = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let day = days[iso] ?? AppleHealthExportImporter.MutableAppleDay(dateIso: iso)
            days[iso] = day
            return (day, Int64(unixSec), mod)
        }
        for s in streams.hr where (28...235).contains(s.bpm) {
            let (d, ep, mod) = dayFor(s.ts)
            d.hrSamples.append((ep, mod, Double(s.bpm)))
        }
        // Group RR beats per 5-min bucket -> true RMSSD
        var rrByBucket: [Int: [Double]] = [:]
        for r in streams.rr where (300...2000).contains(r.rrMs) {
            rrByBucket[(r.ts / 300) * 300, default: []].append(Double(r.rrMs))
        }
        for (bucketTs, seg) in rrByBucket {
            if let rmssd = WhoopPhysiologyEngine.computeRmssdFromRRSegments([seg]) {
                let (d, ep, _) = dayFor(bucketTs)
                d.hrvRmssdSamples.append((ep, rmssd))
            }
        }
        let result = AppleHealthExportImporter.buildSummaries(
            from: days,
            sourceName: "WHOOP BLE",
            profile: userProfile,
            priorHistory: realHistory
        )
        if !result.days.isEmpty {
            applyImportedResult(result, navigateToLatest: false)
            persistState(immediate: true)
            bleLogs = (["✓ Bloque histórico WHOOP guardado (\(result.days.count)d, \(streams.hr.count) FC)"] + bleLogs).prefix(20).map { $0 }
        }
        // Safe-trim ACK strictly after durable persistence!
        whoopBleReader.ackHistoricalChunk(endData: endData)
    }

}
