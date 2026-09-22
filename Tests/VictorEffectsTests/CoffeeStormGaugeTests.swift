import XCTest
@testable import VictorEffects

final class CoffeeStormGaugeTests: XCTestCase {
    func testFourInASecondIsNotAStorm() {
        var g = CoffeeStormGauge()
        for i in 0..<4 { XCTAssertFalse(g.record(at: 10 + Double(i) * 0.2)) }
        XCTAssertEqual(g.intensity(at: 10.8), 0)
    }

    func testTheFifthInASecondTripsIt() {
        var g = CoffeeStormGauge()
        for i in 0..<4 { g.record(at: 10 + Double(i) * 0.2) }
        XCTAssertTrue(g.record(at: 10.8))
        XCTAssertGreaterThan(g.intensity(at: 10.8), 0)
    }

    func testFiveSpreadOverTwoSecondsIsCalm() {
        var g = CoffeeStormGauge()
        for i in 0..<5 { XCTAssertFalse(g.record(at: 10 + Double(i) * 0.45)) }
    }

    func testIntensityGrowsWithRateAndCapsAtTwiceTheThreshold() {
        var g = CoffeeStormGauge()
        for i in 0..<5 { g.record(at: 10 + Double(i) * 0.1) }
        let five = g.intensity(at: 10.4)
        for i in 5..<8 { g.record(at: 10 + Double(i) * 0.1) }
        let eight = g.intensity(at: 10.7)
        for i in 8..<12 { g.record(at: 10 + Double(i) * 0.05) }
        let twelve = g.intensity(at: 10.75)
        XCTAssertGreaterThan(eight, five)
        XCTAssertEqual(eight, 1, accuracy: 0.001)
        XCTAssertEqual(twelve, 1, accuracy: 0.001)
    }

    func testStormLingersThenFadesOut() {
        var g = CoffeeStormGauge()
        for i in 0..<6 { g.record(at: 10 + Double(i) * 0.1) }
        XCTAssertTrue(g.isStorm(at: 11.5))
        // Half way through the linger the tail is still felt, but weaker.
        let mid = g.intensity(at: 11.5)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 0.3)
        XCTAssertTrue(g.isStorm(at: 12.49))
        XCTAssertFalse(g.isStorm(at: 12.51))
        XCTAssertEqual(g.intensity(at: 12.51), 0)
    }

    func testASecondSalvoInsideTheLingerKeepsItOn() {
        var g = CoffeeStormGauge()
        for i in 0..<6 { g.record(at: 10 + Double(i) * 0.1) }
        for i in 0..<6 { XCTAssertTrue(g.record(at: 11.8 + Double(i) * 0.1)) }
        XCTAssertTrue(g.isStorm(at: 14.2))
        XCTAssertFalse(g.isStorm(at: 14.4))
    }

    func testALongSalvoEscalatesEvenAtASteadyRate() {
        var g = CoffeeStormGauge()
        // A steady 6/s: rate-wise that is intensity 0.5 forever.
        for i in 0..<6 { g.record(at: 10 + Double(i) / 6) }
        let early = g.intensity(at: 11.0)
        for i in 6..<30 { g.record(at: 10 + Double(i) / 6) }
        let late = g.intensity(at: 15.0)
        XCTAssertEqual(early, 0.5, accuracy: 0.01)
        XCTAssertEqual(late, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(g.stormCount, 24)
    }

    func testEscalationResetsOnceTheStormHasPassed() {
        var g = CoffeeStormGauge()
        for i in 0..<30 { g.record(at: 10 + Double(i) / 6) }
        XCTAssertFalse(g.record(at: 30))
        XCTAssertEqual(g.stormCount, 0)
    }
}
