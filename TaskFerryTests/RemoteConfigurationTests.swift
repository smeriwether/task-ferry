import XCTest

final class RemoteConfigurationTests: XCTestCase {
    func testAcceptsAndNormalizesHTTPSConfiguration() throws {
        let configuration = try RemoteConfiguration(
            endpoint: "  https://example.com/base///  ",
            accessClientID: " client-id ",
            accessClientSecret: " secret ",
            bridgeToken: " token "
        )

        XCTAssertEqual(configuration.endpoint.absoluteString, "https://example.com/base")
        XCTAssertEqual(configuration.accessClientID, "client-id")
        XCTAssertEqual(configuration.accessClientSecret, "secret")
        XCTAssertEqual(configuration.bridgeToken, "token")
    }

    func testRejectsInsecureEndpoint() {
        XCTAssertThrowsError(try RemoteConfiguration(
            endpoint: "http://example.com",
            accessClientID: "",
            accessClientSecret: "",
            bridgeToken: "token"
        ))
    }

    func testRejectsEndpointCredentialsAndQuery() {
        XCTAssertThrowsError(try RemoteConfiguration(
            endpoint: "https://user@example.com?v=1",
            accessClientID: "",
            accessClientSecret: "",
            bridgeToken: "token"
        ))
    }

    func testRequiresPairedCloudflareCredentials() {
        XCTAssertThrowsError(try RemoteConfiguration(
            endpoint: "https://example.com",
            accessClientID: "client-id",
            accessClientSecret: "",
            bridgeToken: "token"
        ))
    }

    func testRequiresBridgeToken() {
        XCTAssertThrowsError(try RemoteConfiguration(
            endpoint: "https://example.com",
            accessClientID: "",
            accessClientSecret: "",
            bridgeToken: ""
        ))
    }
}
