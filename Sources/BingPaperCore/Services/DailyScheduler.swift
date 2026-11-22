import Foundation

/// Pure scheduling calculator for daily Bing wallpaper updates.
/// Handles scheduled daily times, missed updates after sleep/shutdown, and calendar day rollovers.
public struct DailyScheduler: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Computes the next wall-clock `Date` at `(hour, minute)` strictly after `now`.
    public func nextScheduledDate(hour: Int, minute: Int, after now: Date = Date()) -> Date {
        let clampedHour = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = clampedHour
        components.minute = clampedMinute
        components.second = 0

        if let todayTarget = calendar.date(from: components), todayTarget > now {
            return todayTarget
        }

        let startOfToday = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return now.addingTimeInterval(86_400)
        }
        var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        tomorrowComponents.hour = clampedHour
        tomorrowComponents.minute = clampedMinute
        tomorrowComponents.second = 0

        return calendar.date(from: tomorrowComponents) ?? now.addingTimeInterval(86_400)
    }

    /// Returns `true` when an automatic check should run now:
    /// - Never updated before, OR
    /// - Last update was on an earlier calendar day (after today's scheduled time, or more than 24h ago), OR
    /// - Bing's last applied `startdate` does not yet match today's `YYYYMMDD` and we are past the scheduled time (or a retry interval has elapsed).
    public func isUpdateDue(
        lastSuccessfulUpdate: Date?,
        lastAppliedBingStartDate: String?,
        scheduledHour: Int,
        scheduledMinute: Int,
        now: Date = Date()
    ) -> Bool {
        guard let lastSuccessfulUpdate else {
            return true
        }

        // If more than 24 hours have passed, always check.
        if now.timeIntervalSince(lastSuccessfulUpdate) >= 86_400 {
            return true
        }

        let todayKey = Self.bingDateString(for: now, calendar: calendar)

        // If we already applied today's Bing image (by Bing's own startdate) AND updated today, we're done.
        if lastAppliedBingStartDate == todayKey && calendar.isDate(lastSuccessfulUpdate, inSameDayAs: now) {
            return false
        }

        // Build today's scheduled trigger time.
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = max(0, min(23, scheduledHour))
        components.minute = max(0, min(59, scheduledMinute))
        components.second = 0

        guard let todayTarget = calendar.date(from: components) else {
            return !calendar.isDate(lastSuccessfulUpdate, inSameDayAs: now)
        }

        // If we haven't updated since today's scheduled time AND now >= todayTarget, it's due!
        if now >= todayTarget && lastSuccessfulUpdate < todayTarget {
            return true
        }

        // If we checked earlier today before Bing published the new day's image (e.g. timezone offset),
        // allow a fresh check after 2 hours if Bing's startdate still isn't today's date.
        if lastAppliedBingStartDate != todayKey && now.timeIntervalSince(lastSuccessfulUpdate) >= 7_200 {
            return true
        }

        return false
    }

    public static func bingDateString(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let y = components.year ?? 2026
        let m = components.month ?? 1
        let d = components.day ?? 1
        return String(format: "%04d%02d%02d", y, m, d)
    }
}
