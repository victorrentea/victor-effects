import XCTest
@testable import VictorEffects

final class CoffeeStormGaugeTests: XCTestCase {
    func testThreeInASecondIsNotASalvo() {
        var g = CoffeeStormGauge()
        for i in 0..<3 { XCTAssertFalse(g.record(at: 10 + Double(i) * 0.3)) }
        XCTAssertEqual(g.intensity(at: 10.8), 0)
    }

    func testTheFourthInASecondTripsIt() {
        var g = CoffeeStormGauge()
        for i in 0..<3 { g.record(at: 10 + Double(i) * 0.3) }
        XCTAssertTrue(g.record(at: 10.9))
        XCTAssertGreaterThan(g.intensity(at: 10.9), 0)
    }

    func testFourSpreadOverTwoSecondsIsCalm() {
        var g = CoffeeStormGauge()
        for i in 0..<4 { XCTAssertFalse(g.record(at: 10 + Double(i) * 0.6)) }
    }

    func testIntensityGrowsWithRateAndCapsAtTwiceTheThreshold() {
        var g = CoffeeStormGauge()
        for i in 0..<4 { g.record(at: 10 + Double(i) * 0.1) }
        let four = g.intensity(at: 10.3)
        for i in 4..<6 { g.record(at: 10 + Double(i) * 0.1) }
        let six = g.intensity(at: 10.5)
        for i in 6..<10 { g.record(at: 10 + Double(i) * 0.05) }
        let ten = g.intensity(at: 10.55)
        XCTAssertGreaterThan(six, four)
        XCTAssertEqual(six, 1, accuracy: 0.001)
        XCTAssertEqual(ten, 1, accuracy: 0.001)
    }

    func testSalvoLingersThenFadesOut() {
        var g = CoffeeStormGauge()
        for i in 0..<5 { g.record(at: 10 + Double(i) * 0.1) }
        XCTAssertTrue(g.isStorm(at: 11.5))
        // Half way through the linger the tail is still felt, but weaker.
        let mid = g.intensity(at: 11.5)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 0.3)
        XCTAssertTrue(g.isStorm(at: 12.39))
        XCTAssertFalse(g.isStorm(at: 12.41))
        XCTAssertEqual(g.intensity(at: 12.41), 0)
    }

    func testLingerIsConfigurable() {
        // The animator arms explosions for 10 s, not the 2 s default.
        var g = CoffeeStormGauge()
        g.linger = 10
        for i in 0..<5 { g.record(at: 10 + Double(i) * 0.1) }
        XCTAssertTrue(g.isStorm(at: 20.3))
        XCTAssertFalse(g.isStorm(at: 20.5))
    }

    func testASecondSalvoInsideTheLingerKeepsItOn() {
        var g = CoffeeStormGauge()
        for i in 0..<5 { g.record(at: 10 + Double(i) * 0.1) }
        for i in 0..<5 { XCTAssertTrue(g.record(at: 11.8 + Double(i) * 0.1)) }
        XCTAssertTrue(g.isStorm(at: 14.1))
        XCTAssertFalse(g.isStorm(at: 14.3))
    }

    func testALongSalvoEscalatesEvenAtASteadyRate() {
        var g = CoffeeStormGauge()
        // A steady 4.5/s: rate-wise that is intensity 0.5 forever.
        for i in 0..<5 { g.record(at: 10 + Double(i) / 4.5) }
        let early = g.intensity(at: 10.9)
        for i in 5..<30 { g.record(at: 10 + Double(i) / 4.5) }
        let late = g.intensity(at: 16.5)
        XCTAssertLessThan(early, 1)
        XCTAssertEqual(late, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(g.stormCount, 24)
    }

    func testEscalationResetsOnceTheSalvoHasPassed() {
        var g = CoffeeStormGauge()
        for i in 0..<30 { g.record(at: 10 + Double(i) / 4.5) }
        XCTAssertFalse(g.record(at: 40))
        XCTAssertEqual(g.stormCount, 0)
    }
}
