import XCTest

final class AuthenticationUITests: XCTestCase {
    func testLoginScreenExposesRecoveryAndRegistration() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Tạo tài khoản"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Quên mật khẩu?"].exists)
    }
}
