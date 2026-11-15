import XCTest
@testable import Claudy

/// What the hour does to the agent room: the sun's place, the city's windows, the lamps.
final class RoomSkyTests: XCTestCase {

    func testTheSunIsInTheMiddleOfTheWindowAtNoon() throws {
        let sun = try XCTUnwrap(RoomSky(hour: 12).sun)
        XCTAssertEqual(sun.across, 0.5, accuracy: 0.001)
        XCTAssertEqual(sun.height, 1, accuracy: 0.001)
    }

    func testTheSunRisesOnTheLeftAndSetsOnTheRight() throws {
        let morning = try XCTUnwrap(RoomSky(hour: 8).sun), afternoon = try XCTUnwrap(RoomSky(hour: 16).sun)
        XCTAssertLessThan(morning.across, 0.5)
        XCTAssertGreaterThan(afternoon.across, 0.5)
        XCTAssertNil(RoomSky(hour: 20).sun)
        XCTAssertNil(RoomSky(hour: 3).sun)
    }

    func testTheMoonIsHighestAtMidnightAndGoneByDay() throws {
        let moon = try XCTUnwrap(RoomSky(hour: 0).moon)
        XCTAssertEqual(moon.across, 0.5, accuracy: 0.001)
        XCTAssertNil(RoomSky(hour: 12).moon)
    }

    func testNoWindowOfTheCityIsLitByDay() {
        XCTAssertEqual(RoomSky(hour: 12).litShare, 0)
        XCTAssertEqual(RoomSky(hour: 15).litShare, 0)
    }

    func testTheCityLightsUpThroughTheEveningThenGoesToSleep() {
        let share = { (hour: Double) in RoomSky(hour: hour).litShare }
        XCTAssertGreaterThan(share(17.5), 0)
        XCTAssertLessThan(share(17.5), share(19))
        XCTAssertLessThan(share(19), share(21))
        XCTAssertGreaterThan(share(21), 0.9)
        XCTAssertGreaterThan(share(21), share(22.5))
        XCTAssertGreaterThan(share(22.5), share(23.9))
        XCTAssertGreaterThan(share(23.9), share(3))
    }

    func testTheRoomIsLeftAsDrawnInFullDaylight() {
        XCTAssertNil(RoomSky(hour: 12).dim)
        XCTAssertFalse(RoomSky(hour: 12).hasLamps)
        XCTAssertEqual(RoomSky(hour: 12).darkness, 0)
    }

    func testNightDimsTheRoomAndTurnsTheLampsOn() {
        let night = RoomSky(hour: 23)
        XCTAssertEqual(night.dim, 0x7A80AA)
        XCTAssertTrue(night.hasLamps)
        XCTAssertEqual(night.darkness, 1)
        XCTAssertEqual(night.starlight, 1)
    }

    func testTheSkyBlendsFromOneMomentToTheNext() {
        let before = RoomSky(hour: 16).bands, during = RoomSky(hour: 17).bands, after = RoomSky(hour: 18.25).bands
        XCTAssertNotEqual(during, before)
        XCTAssertNotEqual(during, after)
        XCTAssertEqual(RoomSky.mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
    }

    func testAnHourPastMidnightWrapsAround() {
        XCTAssertEqual(RoomSky(hour: 25).hour, 1)
        XCTAssertEqual(RoomSky(hour: -1).hour, 23)
    }

    func testADayAlwaysHasTheSameWeather() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 8)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 22)))
        XCTAssertEqual(RoomWeather.of(morning, calendar: calendar), RoomWeather.of(evening, calendar: calendar))
    }

    func testAYearHasEveryWeatherAndSnowOnlyInWinter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        var seen: [RoomWeather: Int] = [:]
        for day in 0..<365 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: day, to: start))
            let weather = RoomWeather.of(date, calendar: calendar)
            seen[weather, default: 0] += 1
            if weather == .snow {
                XCTAssertTrue([12, 1, 2].contains(calendar.component(.month, from: date)), "snow on \(date)")
            }
        }
        XCTAssertEqual(Set(seen.keys), Set(RoomWeather.allCases))
        XCTAssertGreaterThan(seen[.clear] ?? 0, 120)
    }

    func testAChosenWeatherWinsOverTheDaysOwn() {
        let date = Date(timeIntervalSince1970: 1_793_468_000)
        XCTAssertEqual(RoomWeather.chosen("snow", at: date), .snow)
        XCTAssertEqual(RoomWeather.chosen(RoomWeather.asItComes, at: date), RoomWeather.of(date))
        XCTAssertTrue(RoomWeather.rain.isFalling)
        XCTAssertFalse(RoomWeather.overcast.isFalling)
    }

    func testAHeldLightGivesItsOwnHourAndTheClockGivesTheMacs() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 21, minute: 30)))
        XCTAssertEqual(RoomLight.noon.hour(at: date, calendar: calendar), 12)
        XCTAssertEqual(RoomLight.clock.hour(at: date, calendar: calendar), 21.5, accuracy: 0.001)
    }
}
