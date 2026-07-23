import XCTest
@testable import CineViet

final class AuthModelsTests: XCTestCase {
    func testAuthResponseAcceptsLegacyToken() throws {
        let response = try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"token":"access","refreshToken":"refresh"}"#.utf8))
        XCTAssertEqual(try response.tokens(), TokenPair(accessToken: "access", refreshToken: "refresh"))
    }
    func testUserDecodesUnderscoreIdentifierAndVIP() throws {
        let user = try JSONDecoder().decode(User.self, from: Data(#"{"_id":"42","email":"a@b.c","is_vip":true}"#.utf8))
        XCTAssertEqual(user.id, "42"); XCTAssertTrue(user.isVip)
    }
}
