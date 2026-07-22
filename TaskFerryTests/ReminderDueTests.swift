import XCTest
final class ReminderDueTests: XCTestCase {
    func testDateOnlyRoundTripPreservesNoTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 17, minute: 45)))

        let due = ReminderDue(date: date, includesTime: false, calendar: calendar)

        XCTAssertEqual(due.year, 2026)
        XCTAssertEqual(due.month, 7)
        XCTAssertEqual(due.day, 20)
        XCTAssertNil(due.hour)
        XCTAssertNil(due.minute)
        XCTAssertNil(due.timeZoneIdentifier)
    }

    func testTimedDueRoundTripPreservesTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 17, minute: 45)))

        let due = ReminderDue(date: date, includesTime: true, calendar: calendar)

        XCTAssertEqual(due.hour, 17)
        XCTAssertEqual(due.minute, 45)
        XCTAssertEqual(due.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(due.date(calendar: calendar), date)
    }

    func testOverdueComparesByCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 8)))
        let due = ReminderDue(year: 2026, month: 7, day: 19)

        XCTAssertTrue(due.isBeforeDay(today, calendar: calendar))
        XCTAssertFalse(due.isSameDay(as: today, calendar: calendar))
    }
}
