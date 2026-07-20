import XCTest
final class ProtocolTests: XCTestCase {
    func testRPCRequestRoundTrip() throws {
        let due = ReminderDue(year: 2026, month: 7, day: 21, hour: 9, minute: 30, timeZoneIdentifier: "America/New_York")
        let request = RPCRequest(operation: .upsertReminder, id: "abc", title: "Call dentist", listID: "personal", due: due)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RPCRequest.self, from: data)

        XCTAssertEqual(decoded.operation, .upsertReminder)
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.title, "Call dentist")
        XCTAssertEqual(decoded.listID, "personal")
        XCTAssertEqual(decoded.due, due)
    }

    func testHTTPRequestWaitsForCompleteBody() throws {
        let body = try JSONEncoder().encode(RPCRequest.snapshot)
        let header = "POST /v1/rpc HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nAuthorization: Bearer test\r\n\r\n"
        var complete = Data(header.utf8)
        complete.append(body)

        XCTAssertNil(HTTPRequest.parse(complete.dropLast()))
        let request = try XCTUnwrap(HTTPRequest.parse(complete))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/rpc")
        XCTAssertEqual(request.headers["authorization"], "Bearer test")
        XCTAssertEqual(request.body, body)
    }

    func testHTTPRequestRejectsChunkedBodies() {
        let request = Data("POST /v1/rpc HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        XCTAssertNil(HTTPRequest.parse(request))
    }
}
