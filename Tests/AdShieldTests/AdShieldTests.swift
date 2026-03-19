import XCTest
@testable import AdShield

final class AdShieldTests: XCTestCase {

    func testDetectorReturnsEmptyForEmptyInput() async throws {
        let result = await AdBlockDetector.detect(urls: [])
        XCTAssertEqual(result.count, 0)
    }
}
