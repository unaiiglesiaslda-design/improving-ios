import Foundation

/// Self-contained compressed full backup & restore archive (`.improvingbak`) for AltStore / SideStore / device migrations.
/// Bundles all store state (excluding API keys!) plus MealPhotos and ProfileAvatars into a single portable file.
enum AppBackupService {
    static let currentArchiveVersion = 1
    static let fileExtension = "improvingbak"

    struct BackupEnvelope: Codable {
        let archiveVersion: Int
        let createdAtIso: String
        let appVersion: String
        let snapshotJsonBase64: String
        let mealPhotos: [String: String]     // filename -> base64 JPEG
        let avatarPhotos: [String: String]   // filename -> base64 JPEG
    }

    struct RestoreSummary {
        let snapshotData: Data
        let restoredMealPhotos: Int
        let restoredAvatarPhotos: Int
        let createdAtIso: String
    }

    enum BackupError: LocalizedError {
        case invalidFile
        case decompressionFailed
        case corruptedArchive

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "No se pudo leer el archivo de copia de seguridad."
            case .decompressionFailed: return "El archivo .improvingbak está dañado o tiene un formato no compatible."
            case .corruptedArchive: return "La copia de seguridad no contiene datos válidos de Improving."
            }
        }
    }

    static func createBackupFile(snapshotData: Data) throws -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory

        let mealDir = appSupport.appendingPathComponent("MealPhotos", isDirectory: true)
        let avatarDir = appSupport.appendingPathComponent("ProfileAvatars", isDirectory: true)

        func collectPhotos(in dir: URL, maxTotalBytes: Int) -> [String: String] {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
                return [:]
            }
            var map: [String: String] = [:]
            var used = 0
            for f in files where f.pathExtension.lowercased() == "jpg" || f.pathExtension.lowercased() == "jpeg" || f.pathExtension.lowercased() == "png" {
                guard let data = try? Data(contentsOf: f), !data.isEmpty else { continue }
                guard used + data.count <= maxTotalBytes else { break }
                used += data.count
                map[f.lastPathComponent] = data.base64EncodedString()
            }
            return map
        }

        let mealPhotos = collectPhotos(in: mealDir, maxTotalBytes: 25 * 1024 * 1024)
        let avatarPhotos = collectPhotos(in: avatarDir, maxTotalBytes: 4 * 1024 * 1024)

        let isoFmt = ISO8601DateFormatter()
        let nowIso = isoFmt.string(from: Date())
        let appVer = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"

        let envelope = BackupEnvelope(
            archiveVersion: currentArchiveVersion,
            createdAtIso: nowIso,
            appVersion: appVer,
            snapshotJsonBase64: snapshotData.base64EncodedString(),
            mealPhotos: mealPhotos,
            avatarPhotos: avatarPhotos
        )

        let rawJson = try JSONEncoder().encode(envelope)
        let compressed = try (rawJson as NSData).compressed(using: .lzfse) as Data

        let dateStamp = String(nowIso.prefix(10))
        let outURL = fm.temporaryDirectory.appendingPathComponent("Improving_Backup_\(dateStamp).\(fileExtension)")
        try compressed.write(to: outURL, options: [.atomic, .completeFileProtection])
        return outURL
    }

    static func unpackBackupFile(at url: URL) throws -> RestoreSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: url), !raw.isEmpty else {
            throw BackupError.invalidFile
        }

        // Accept either LZFSE-compressed `.improvingbak` or raw JSON backup/snapshot
        let decodedEnvelope: BackupEnvelope
        if let decompressed = try? (raw as NSData).decompressed(using: .lzfse) as Data,
           let env = try? JSONDecoder().decode(BackupEnvelope.self, from: decompressed) {
            decodedEnvelope = env
        } else if let env = try? JSONDecoder().decode(BackupEnvelope.self, from: raw) {
            decodedEnvelope = env
        } else {
            // Legacy raw `improving_store_v3.json` fallback!
            if (try? JSONSerialization.jsonObject(with: raw)) != nil {
                return RestoreSummary(
                    snapshotData: raw,
                    restoredMealPhotos: 0,
                    restoredAvatarPhotos: 0,
                    createdAtIso: ""
                )
            }
            throw BackupError.decompressionFailed
        }

        guard let snapData = Data(base64Encoded: decodedEnvelope.snapshotJsonBase64), !snapData.isEmpty else {
            throw BackupError.corruptedArchive
        }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let mealDir = appSupport.appendingPathComponent("MealPhotos", isDirectory: true)
        let avatarDir = appSupport.appendingPathComponent("ProfileAvatars", isDirectory: true)
        try? fm.createDirectory(at: mealDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: avatarDir, withIntermediateDirectories: true)

        var mealCount = 0
        for (name, b64) in decodedEnvelope.mealPhotos {
            let safeName = URL(fileURLWithPath: name).lastPathComponent
            guard !safeName.isEmpty, let d = Data(base64Encoded: b64) else { continue }
            let dst = mealDir.appendingPathComponent(safeName)
            if (try? d.write(to: dst, options: [.atomic, .completeFileProtection])) != nil {
                mealCount += 1
            }
        }

        var avatarCount = 0
        for (name, b64) in decodedEnvelope.avatarPhotos {
            let safeName = URL(fileURLWithPath: name).lastPathComponent
            guard !safeName.isEmpty, let d = Data(base64Encoded: b64) else { continue }
            let dst = avatarDir.appendingPathComponent(safeName)
            if (try? d.write(to: dst, options: [.atomic, .completeFileProtection])) != nil {
                avatarCount += 1
            }
        }

        return RestoreSummary(
            snapshotData: snapData,
            restoredMealPhotos: mealCount,
            restoredAvatarPhotos: avatarCount,
            createdAtIso: decodedEnvelope.createdAtIso
        )
    }
}
