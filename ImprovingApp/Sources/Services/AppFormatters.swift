import Foundation

/// Centralized, zero-allocation date formatting utilities.
/// Eliminates dozens of per-frame / per-loop `DateFormatter()` initializations on the main thread
/// while providing 100% thread-safe pure calendar ISO `yyyy-MM-dd` formatting & parsing for background actors/tasks.
enum AppFormatters {
    // MARK: - Thread-Safe Pure Calendar ISO `yyyy-MM-dd` (Safe across @MainActor & Task.detached!)

    private static var gregorianUTC: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    static func isoDayString(from date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2000
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func parseIsoDay(_ raw: String, calendar: Calendar = .current) -> Date? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1900...2100).contains(y), (1...12).contains(m), (1...31).contains(d) else {
            return nil
        }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let dt = calendar.date(from: comps) else { return nil }
        // Verify date did not overflow (e.g. Feb 30 -> Mar 2)
        let verify = calendar.dateComponents([.year, .month, .day], from: dt)
        guard verify.year == y, verify.month == m, verify.day == d else { return nil }
        return dt
    }

    static func hhmmString(from date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    static func hhmmssString(from date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
    }

    // MARK: - MainActor Cached Spanish Display Formatters (Zero ICU table reloads during scrolling!)

    @MainActor static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    @MainActor static let dMMM: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f
    }()

    @MainActor static let dMMMMyyyy: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f
    }()

    @MainActor static let monthYearEs: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    @MainActor static let shortMonthYearEs: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM yyyy"
        return f
    }()

    @MainActor static let weekdayShortEs: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f
    }()

    @MainActor static let dMMMyyyy: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    @MainActor static let weekdayDayMonthEs: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE, d MMM"
        return f
    }()
}
