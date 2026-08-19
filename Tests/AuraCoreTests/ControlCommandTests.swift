import XCTest
@testable import AuraCore

final class ControlCommandTests: XCTestCase {
    private func parse(_ json: String) throws -> ControlCommand {
        try ControlCommand.parse(json: Data(json.utf8))
    }

    func testParsesPushWithAllFields() throws {
        let command = try parse("""
        {"cmd":"activity.push","id":"build","title":"Сборка","subtitle":"linking",
         "symbol":"hammer.fill","tint":"orange","progress":0.4,"ttl":30,"priority":"important"}
        """)

        guard case .push(let payload) = command else {
            return XCTFail("ожидался push, получено \(command)")
        }
        XCTAssertEqual(payload.id, "build")
        XCTAssertEqual(payload.title, "Сборка")
        XCTAssertEqual(payload.progress, 0.4)
        XCTAssertEqual(payload.priority, "important")
    }

    func testParsesRemoveAndRejectsMissingID() throws {
        guard case .remove(let id) = try parse(#"{"cmd":"activity.remove","id":"x"}"#) else {
            return XCTFail("ожидался remove")
        }
        XCTAssertEqual(id, "x")

        XCTAssertThrowsError(try parse(#"{"cmd":"activity.remove"}"#))
    }

    func testRejectsUnknownCommand() {
        XCTAssertThrowsError(try parse(#"{"cmd":"нет такой"}"#)) { error in
            XCTAssertTrue("\(error)".contains("нет такой"))
        }
    }

    func testParsesURLWithPercentEncoding() throws {
        let url = URL(string: "aura://activity/push?id=t1&title=Hello%20World&ttl=8&tint=blue")!
        guard case .push(let payload) = try ControlCommand.parse(url: url) else {
            return XCTFail("ожидался push")
        }
        XCTAssertEqual(payload.title, "Hello World", "значения должны приходить раскодированными")
        XCTAssertEqual(payload.ttl, 8)
    }

    func testParsesURLCommandsWithoutQuery() throws {
        guard case .open = try ControlCommand.parse(url: URL(string: "aura://notch/open")!) else {
            return XCTFail("ожидался open")
        }
        guard case .close = try ControlCommand.parse(url: URL(string: "aura://notch/close")!) else {
            return XCTFail("ожидался close")
        }
    }

    func testURLPushRequiresTitle() {
        let url = URL(string: "aura://activity/push?id=only")!
        XCTAssertThrowsError(try ControlCommand.parse(url: url))
    }
}
