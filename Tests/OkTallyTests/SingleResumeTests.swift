import XCTest
@testable import OkTally

final class SingleResumeTests: XCTestCase {
    func test_fire_executesBodyOnlyOnce() {
        let resumeGuard = SingleResume()
        var callCount = 0

        let firstFired = resumeGuard.fire { callCount += 1 }
        let secondFired = resumeGuard.fire { callCount += 1 }

        XCTAssertTrue(firstFired)
        XCTAssertFalse(secondFired)
        XCTAssertEqual(callCount, 1)
    }

    func test_fire_isSafeUnderConcurrentCalls() {
        let resumeGuard = SingleResume()
        let callCount = NSLock()
        var count = 0
        let iterations = 200
        let expectation = expectation(description: "all fire calls complete")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            resumeGuard.fire {
                callCount.lock()
                count += 1
                callCount.unlock()
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(count, 1, "body must run exactly once even under concurrent racing calls")
    }
}
