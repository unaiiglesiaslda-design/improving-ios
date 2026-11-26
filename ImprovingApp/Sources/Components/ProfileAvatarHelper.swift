import Foundation
import SwiftUI
import UIKit

/// Persists, EXIF-orients, center-crops (512x512 JPEG), and resolves the user's profile avatar
/// inside Application Support using a stable relative filename so it survives iOS container upgrades.
enum ProfilePhotoStorage {
    private static let filePrefix = "improving_avatar_"
    private static let targetSidePx: CGFloat = 512
    private static let imageCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 8
        c.totalCostLimit = 8 * 1024 * 1024
        return c
    }()

    private static var avatarsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ProfileAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func resolveURL(for storedPathOrName: String?) -> URL? {
        guard let raw = storedPathOrName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let fm = FileManager.default
        // Prefer filename lookup inside ProfileAvatars (resilient across iOS sandbox UUID changes!)
        let candidate = avatarsDirectory.appendingPathComponent((raw as NSString).lastPathComponent)
        if fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        if fm.fileExists(atPath: raw) {
            return URL(fileURLWithPath: raw)
        }
        return nil
    }

    static func loadImage(from storedPathOrName: String?) -> UIImage? {
        guard let raw = storedPathOrName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let cacheKey = (raw as NSString).lastPathComponent as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let url = resolveURL(for: raw),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let img = UIImage(data: data) else {
            return nil
        }
        imageCache.setObject(img, forKey: cacheKey, cost: data.count)
        return img
    }

    /// Normalizes orientation, center-crops to square, resizes to max 512x512, and saves JPEG cleanly.
    /// Returns the stored filename (e.g. `improving_avatar_1795465000.jpg`).
    @discardableResult
    static func savePickedImageData(_ rawData: Data) -> String? {
        guard let source = UIImage(data: rawData) else { return nil }
        let normalized = normalizeAndCenterCropSquare(source, targetSide: targetSidePx)
        guard let jpeg = normalized.jpegData(compressionQuality: 0.90) else { return nil }

        let dir = avatarsDirectory
        if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in existing where f.lastPathComponent.hasPrefix(filePrefix) {
                try? FileManager.default.removeItem(at: f)
            }
        }
        let filename = "\(filePrefix)\(Int64(Date().timeIntervalSince1970 * 1000)).jpg"
        let dest = dir.appendingPathComponent(filename)
        do {
            try jpeg.write(to: dest, options: .atomic)
            imageCache.removeAllObjects()
            imageCache.setObject(normalized, forKey: filename as NSString, cost: jpeg.count)
            return filename
        } catch {
            return nil
        }
    }

    static func deleteSavedPhotos() {
        imageCache.removeAllObjects()
        let dir = avatarsDirectory
        if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in existing where f.lastPathComponent.hasPrefix(filePrefix) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    private static func normalizeAndCenterCropSquare(_ image: UIImage, targetSide: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let minSide = min(size.width, size.height)
        let outSide = min(minSide, targetSide)
        let scaleFactor = outSide / minSide
        let drawSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let origin = CGPoint(x: (outSide - drawSize.width) / 2.0, y: (outSide - drawSize.height) / 2.0)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outSide, height: outSide), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

/// Reusable circular profile avatar displaying the user's saved photo with automatic fallback
/// to crisp initials (First + Last) or a clean silhouette icon.
struct UserProfileAvatarView: View {
    let photoPath: String?
    let initials: String
    var size: CGFloat = 32
    var showGradientRing: Bool = false
    var ringWidth: CGFloat = 2.0

    var body: some View {
        let loadedImg = ProfilePhotoStorage.loadImage(from: photoPath)
        let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines)

        ZStack {
            if let img = loadedImg {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BevelColors.skySoftBg, BevelColors.indigoSoftBg],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                if !cleanInitials.isEmpty {
                    Text(cleanInitials)
                        .font(.system(size: max(10, min(size * 0.37, 32)), weight: .bold, design: .rounded))
                        .foregroundColor(BevelColors.skyBlue)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundColor(BevelColors.skyBlue)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showGradientRing {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [BevelColors.greenPrimary, BevelColors.indigoEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: ringWidth
                    )
            }
        }
    }
}
