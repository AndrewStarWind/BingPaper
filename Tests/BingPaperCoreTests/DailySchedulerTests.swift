import BingPaperCore
import Foundation
import Testing

@Suite("DailyScheduler")
struct DailySchedulerTests {
    private var fixedCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        fixedCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Schedules later today when target time has not yet passed")
    func schedulesLaterToday() {
        let scheduler = DailyScheduler(calendar: fixedCalendar)
        let now = date(2026, 11, 22, 8, 15)
        let next = scheduler.nextScheduledDate(hour: 9, minute: 0, after: now)
        #expect(next == date(2026, 11, 22, 9, 0))
    }

    @Test("Schedules tomorrow when target time already passed today")
    func schedulesTomorrow() {
        let scheduler = DailyScheduler(calendar: fixedCalendar)
        let now = date(2026, 11, 22, 9, 5)
        let next = scheduler.nextScheduledDate(hour: 9, minute: 0, after: now)
        #expect(next == date(2026, 11, 23, 9, 0))
    }

    @Test("Marks update due when never updated before")
    func dueOnFirstRun() {
        let scheduler = DailyScheduler(calendar: fixedCalendar)
        let due = scheduler.isUpdateDue(
            lastSuccessfulUpdate: nil,
            lastAppliedBingStartDate: nil,
            scheduledHour: 9,
            scheduledMinute: 0,
            now: date(2026, 11, 22, 7, 0)
        )
        #expect(due == true)
    }

    @Test("Skips update when today's Bing image was already applied today")
    func skipsWhenTodayAlreadyApplied() {
        let scheduler = DailyScheduler(calendar: fixedCalendar)
        let due = scheduler.isUpdateDue(
            lastSuccessfulUpdate: date(2026, 11, 22, 9, 1),
            lastAppliedBingStartDate: "20261122",
            scheduledHour: 9,
            scheduledMinute: 0,
            now: date(2026, 11, 22, 14, 0)
        )
        #expect(due == false)
    }

    @Test("Marks update due on wake after missed scheduled time")
    func dueAfterMissedScheduledTime() {
        let scheduler = DailyScheduler(calendar: fixedCalendar)
        let due = scheduler.isUpdateDue(
            lastSuccessfulUpdate: date(2026, 11, 21, 9, 1),
            lastAppliedBingStartDate: "20261121",
            scheduledHour: 9,
            scheduledMinute: 0,
            now: date(2026, 11, 22, 11, 30)
        )
        #expect(due == true)
    }

    @Test("Allows retry 2 hours later if Bing had not rolled over startdate yet")
    func retriesWhenBingTimezoneHasNotRolledOverYet() {
        let scheduler = DailyScheduler(calendar: fixedCalendar)
        let due = scheduler.isUpdateDue(
            lastSuccessfulUpdate: date(2026, 11, 22, 6, 0),
            lastAppliedBingStartDate: "20261121",
            scheduledHour: 9,
            scheduledMinute: 0,
            now: date(2026, 11, 22, 8, 15)
        )
        #expect(due == true)
    }
}
