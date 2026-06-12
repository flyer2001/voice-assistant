import XCTest
@testable import VKAdapter

final class VKConfigTests: XCTestCase {
    func testFromEnvironment_validInputs_parsesAllFields() throws {
        let env = [
            "VK_BOT_TOKEN": "vk1.a.sample_token_value",
            "VK_BOT_GROUP_ID": "123456789",
            "VK_BOT_OWNER_IDS": "111, 222,333",
            "VK_API_VERSION": "5.200"
        ]

        let config = try VKConfig.fromEnvironment(env)

        XCTAssertEqual(config.botToken, "vk1.a.sample_token_value")
        XCTAssertEqual(config.groupId, 123456789)
        XCTAssertEqual(config.ownerIds, [111, 222, 333])
        XCTAssertEqual(config.apiVersion, "5.200")
    }

    func testFromEnvironment_apiVersionAbsent_defaults_5_199() throws {
        let env = [
            "VK_BOT_TOKEN": "t",
            "VK_BOT_GROUP_ID": "1",
            "VK_BOT_OWNER_IDS": "42"
        ]

        let config = try VKConfig.fromEnvironment(env)

        XCTAssertEqual(config.apiVersion, "5.199")
    }

    func testFromEnvironment_missingToken_throwsMissing() {
        let env = [
            "VK_BOT_GROUP_ID": "1",
            "VK_BOT_OWNER_IDS": "42"
        ]

        XCTAssertThrowsError(try VKConfig.fromEnvironment(env)) { error in
            XCTAssertEqual(error as? VKConfigError, .missing(key: "VK_BOT_TOKEN"))
        }
    }

    func testFromEnvironment_emptyToken_throwsMissing() {
        let env = [
            "VK_BOT_TOKEN": "",
            "VK_BOT_GROUP_ID": "1",
            "VK_BOT_OWNER_IDS": "42"
        ]

        XCTAssertThrowsError(try VKConfig.fromEnvironment(env)) { error in
            XCTAssertEqual(error as? VKConfigError, .missing(key: "VK_BOT_TOKEN"))
        }
    }

    func testFromEnvironment_nonNumericGroupId_throwsInvalid() {
        let env = [
            "VK_BOT_TOKEN": "t",
            "VK_BOT_GROUP_ID": "abc",
            "VK_BOT_OWNER_IDS": "42"
        ]

        XCTAssertThrowsError(try VKConfig.fromEnvironment(env)) { error in
            XCTAssertEqual(error as? VKConfigError, .invalidValue(key: "VK_BOT_GROUP_ID", value: "abc"))
        }
    }

    func testFromEnvironment_ownerIdsAllNonNumeric_throwsInvalid() {
        let env = [
            "VK_BOT_TOKEN": "t",
            "VK_BOT_GROUP_ID": "1",
            "VK_BOT_OWNER_IDS": "alice,bob"
        ]

        XCTAssertThrowsError(try VKConfig.fromEnvironment(env)) { error in
            XCTAssertEqual(error as? VKConfigError, .invalidValue(key: "VK_BOT_OWNER_IDS", value: "alice,bob"))
        }
    }
}
