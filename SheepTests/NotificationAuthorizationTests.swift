import XCTest
@testable import Sheep

final class NotificationAuthorizationTests: XCTestCase {
    func testGateCoalescesConcurrentCallsIntoOneRequest() async {
        let lock = NSLock()
        var calls = 0
        let gate = AuthorizationGate {
            lock.lock(); calls += 1; lock.unlock()
            try? await Task.sleep(nanoseconds: 80_000_000)
            return true
        }
        async let a = gate.ensure()
        async let b = gate.ensure()
        async let c = gate.ensure()
        let results = await [a, b, c]
        XCTAssertEqual(results, [true, true, true])
        XCTAssertEqual(calls, 1, "a second in-flight requestAuthorization is what poisons the simulator")
    }

    func testGateDoesNotRequestAgainAfterTheFirstSettles() async {
        let lock = NSLock()
        var calls = 0
        let gate = AuthorizationGate {
            lock.lock(); calls += 1; lock.unlock()
            return true
        }
        let first = await gate.ensure()
        let second = await gate.ensure()
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(calls, 1)
    }

    func testGateResetAllowsAnotherRequest() async {
        var calls = 0
        let gate = AuthorizationGate {
            calls += 1
            return calls == 1
        }
        let first = await gate.ensure()
        gate.reset()
        let again = await gate.ensure()
        XCTAssertTrue(first)
        XCTAssertFalse(again)
        XCTAssertEqual(calls, 2)
    }
}
