import XCTest
@testable import SnagItCore

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(SnagItCore.version.isEmpty)
    }
}
