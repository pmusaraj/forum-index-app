import Foundation

public struct FeedbackSubmission: Codable, Equatable, Sendable {
    public static let messageLimit = 1_000
    public let requestID: UUID
    public let message: String
    public let appVersion: String
    public let appBuild: String
    public let platform: String
    public let osVersion: String

    public init(requestID: UUID, message: String,
                appVersion: String, appBuild: String, platform: String, osVersion: String) {
        self.requestID = requestID
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.platform = platform
        self.osVersion = osVersion
    }

    public var isValid: Bool {
        !message.isEmpty && message.unicodeScalars.count <= Self.messageLimit
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case message, platform
        case appVersion = "app_version"
        case appBuild = "app_build"
        case osVersion = "os_version"
    }
}
