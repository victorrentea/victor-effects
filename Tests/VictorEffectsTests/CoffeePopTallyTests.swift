import XCTest
@testable import VictorEffects

final class CoffeePopTallyTests: XCTestCase {
    func testSixPopsAreNotCriticalTheSeventhIs() {
        var t = CoffeePopTally()
        for i in 0..<6 { t.recordPop(at: 100 + Double(i) * 30) }
        XCTAssertFalse(t.isCritical(at: 300))
        t.recordPop(at: 301)
        XCTAssertTrue(t.isCritical(at: 301))
    }

    func testCriticalMassWearsOffWhenThePopsAgeOut() {
        var t = CoffeePopTally()
        for i in 0..<7 { t.recordPop(at: 100 + Double(i)) }
        XCTAssertTrue(t.isCritical(at: 106))
        XCTAssertFalse(t.isCritical(at: 100 + 601))
    }

    func testRocketBurstsNeverCountTowardCriticalMass() {
        var t = CoffeePopTally()
        for i in 0..<20 { t.recordBurst(at: 100 + Double(i)) }
        XCTAssertFalse(t.isCritical(at: 120))
    }

    func testThreeInASecondStayCalmTheFourthGrowsAndTheFifthGrowsMore() {
        var t = CoffeePopTally()
        XCTAssertEqual(t.violence(at: 10.0), 1)
        t.recordPop(at: 10.0)
        XCTAssertEqual(t.violence(at: 10.2), 1)
        t.recordPop(at: 10.2)
        XCTAssertEqual(t.violence(at: 10.4), 1)
        t.recordPop(at: 10.4)
        let fourth = t.violence(at: 10.6)
        XCTAssertGreaterThan(fourth, 1)
        t.recordPop(at: 10.6)
        XCTAssertGreaterThan(t.violence(at: 10.8), fourth)
    }

    func testEscalationIsCappedAndSpreadOutPopsStayCalm() {
        var t = CoffeePopTally()
        for i in 0..<40 { t.recordBurst(at: 10 + Double(i) * 0.01) }
        XCTAssertEqual(t.violence(at: 10.4), t.maxViolence)
        var calm = CoffeePopTally()
        for i in 0..<10 { calm.recordPop(at: 10 + Double(i) * 0.6) }
        XCTAssertEqual(calm.violence(at: 16.1), 1)
    }
}
