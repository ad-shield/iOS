import XCTest
@testable import AdShield

final class AdShieldTests: XCTestCase {

    func testDetectorReturnsNonNil() async throws {
        // On a machine with network, detect() should return non-nil
        let result = try await AdBlockDetector.detect()
        XCTAssertNotNil(result)
    }
}
