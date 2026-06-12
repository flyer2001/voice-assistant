import Foundation

public struct VKConfig: Sendable {
    public let botToken: String
    public let groupId: Int
    public let ownerIds: Set<Int>
    public let apiVersion: String

    public init(
        botToken: String,
        groupId: Int,
        ownerIds: Set<Int>,
        apiVersion: String = "5.199"
    ) {
        self.botToken = botToken
        self.groupId = groupId
        self.ownerIds = ownerIds
        self.apiVersion = apiVersion
    }

    public static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> VKConfig {
        let token = try require(env, "VK_BOT_TOKEN")
        let groupIdStr = try require(env, "VK_BOT_GROUP_ID")
        let ownerIdsStr = try require(env, "VK_BOT_OWNER_IDS")

        guard let groupId = Int(groupIdStr) else {
            throw VKConfigError.invalidValue(key: "VK_BOT_GROUP_ID", value: groupIdStr)
        }

        let ownerIds = Set(
            ownerIdsStr
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        )
        guard !ownerIds.isEmpty else {
            throw VKConfigError.invalidValue(key: "VK_BOT_OWNER_IDS", value: ownerIdsStr)
        }

        return VKConfig(
            botToken: token,
            groupId: groupId,
            ownerIds: ownerIds,
            apiVersion: env["VK_API_VERSION"] ?? "5.199"
        )
    }

    private static func require(_ env: [String: String], _ key: String) throws -> String {
        guard let value = env[key], !value.isEmpty else {
            throw VKConfigError.missing(key: key)
        }
        return value
    }
}

public enum VKConfigError: Error, CustomStringConvertible, Equatable {
    case missing(key: String)
    case invalidValue(key: String, value: String)

    public var description: String {
        switch self {
        case .missing(let key):
            return "VKConfig: missing required env var '\(key)'"
        case .invalidValue(let key, let value):
            return "VKConfig: invalid value for '\(key)': '\(value)'"
        }
    }
}
