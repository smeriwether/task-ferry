import XCTest

final class BridgeTokenTests: XCTestCase {
    func testRandomTokenUsesEasyToTranscribeGroups() throws {
        let token = try KeychainStore().randomToken()
        let groups = token.split(separator: "-")
        let allowed = CharacterSet(charactersIn: "23456789ABCDEFGHJKMNPQRSTVWXYZ")

        XCTAssertEqual(groups.count, 6)
        XCTAssertTrue(groups.allSatisfy { $0.count == 4 })
        XCTAssertNil(token.unicodeScalars.first { !allowed.contains($0) && $0 != "-" })
    }
}
