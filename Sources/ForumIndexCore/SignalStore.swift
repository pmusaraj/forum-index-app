import Foundation
import Observation
import Security

public protocol SignalTokenStore: Sendable {
    func readToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
    func deleteToken(matching token: String) throws -> Bool
}


public enum SignalTokenStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
}

public final class KeychainSignalTokenStore: SignalTokenStore, @unchecked Sendable {
    public static let shared = KeychainSignalTokenStore()

    private enum Cache { case unloaded, loaded(String?) }

    private let service: String
    private let account = "signal-bearer-token"
    private let lock = NSLock()
    private var cache = Cache.unloaded

    public init(service: String = "com.musaraj.ForumIndex.signal-enrollment") {
        self.service = service
    }

    public func readToken() throws -> String? {
        try lock.withLock { try readTokenLocked() }
    }

    public func saveToken(_ token: String) throws {
        try lock.withLock {
            guard !token.isEmpty else { throw SignalTokenStoreError.keychain(errSecParam) }
            let data = Data(token.utf8)
            let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = baseQuery
                item[kSecValueData] = data
                item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let addStatus = SecItemAdd(item as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw SignalTokenStoreError.keychain(addStatus) }
            } else if status != errSecSuccess {
                throw SignalTokenStoreError.keychain(status)
            }
            cache = .loaded(token)
        }
    }

    public func deleteToken() throws {
        try lock.withLock { try deleteTokenLocked() }
    }

    public func deleteToken(matching token: String) throws -> Bool {
        try lock.withLock {
            guard try readTokenLocked() == token else { return false }
            try deleteTokenLocked()
            return true
        }
    }

    private func readTokenLocked() throws -> String? {
        if case let .loaded(token) = cache { return token }

        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            cache = .loaded(nil)
            return nil
        }
        guard status == errSecSuccess else { throw SignalTokenStoreError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw SignalTokenStoreError.keychain(errSecDecode)
        }
        cache = .loaded(token)
        return token
    }

    private func deleteTokenLocked() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SignalTokenStoreError.keychain(status)
        }
        cache = .loaded(nil)
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

@MainActor
@Observable
public final class SignalStore {
    private enum ActionReportOutcome {
        case success
        case invalidBearerToken
        case failure
    }

    public private(set) var isEnrolled = false
    public private(set) var isEnrolling = false
    public private(set) var enrollmentError: String?
    public private(set) var contributionError: String?
    public private(set) var installation: SignalInstallation?

    public var forYouEligible: Bool {
        isEnrolled && installation?.forYouEligible == true
    }

    @ObservationIgnored private var installationRefreshGeneration = 0

    // Refresh eligibility without blocking subsequent read reports.
    private func refreshReadEligibility() async {
        guard let token else { return }
        installationRefreshGeneration += 1
        let generation = installationRefreshGeneration
        do {
            let refreshed = try await apiClient.fetchInstallation(bearerToken: token)
            guard self.token == token, installationRefreshGeneration == generation else { return }
            installation = refreshed
        } catch ForumIndexAPIError.invalidBearerToken {
            guard self.token == token else { return }
            invalidateEnrollment(rejectedToken: token)
        } catch {
            // A later read or launch will retry; keep the last known status.
        }
    }

    private let apiClient: any SignalAPIClientProtocol
    private let tokenStore: any SignalTokenStore
    private let deviceCheckToken: @Sendable () async throws -> String?
    private let defaults: UserDefaults
    private let valuesKey = "topic-signal-values-v1"
    private let optOutKey = "contributions-opted-out-v1"
    private let displayNameKey = "contributor-display-name-v1"
    private var token: String?
    private var values: [Int: Int] = [:]
    private var updatingTopicIDs: Set<Int> = []
    private var errors: [Int: String] = [:]
    @ObservationIgnored private var actionReportTasks: [Int: Task<ActionReportOutcome, Never>] = [:]
    @ObservationIgnored private var actionReportGenerations: [Int: Int] = [:]

    public init(
        apiClient: any SignalAPIClientProtocol,
        tokenStore: any SignalTokenStore,
        defaults: UserDefaults = .standard,
        deviceCheckToken: @escaping @Sendable () async throws -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.deviceCheckToken = deviceCheckToken
        if let data = defaults.data(forKey: valuesKey) {
            values = (try? JSONDecoder().decode([Int: Int].self, from: data)) ?? [:]
        }
        do {
            token = defaults.bool(forKey: optOutKey) ? nil : try tokenStore.readToken()
            isEnrolled = token != nil
        } catch {
            enrollmentError = "Couldn’t access secure storage."
        }
    }

    public var defaultDisplayName: String {
        if let name = defaults.string(forKey: displayNameKey) { return name }
        let name = "Reader-\(UUID().uuidString.prefix(8))"
        defaults.set(name, forKey: displayNameKey)
        return name
    }

    public func enrollAutomaticallyIfNeeded(deviceName: String) async {
        guard !isEnrolled, !isEnrolling, enrollmentError == nil,
              !defaults.bool(forKey: optOutKey), !Task.isCancelled else { return }
        await enroll(displayName: defaultDisplayName, deviceName: deviceName)
    }

    @discardableResult
    public func enroll(displayName: String, deviceName: String) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            enrollmentError = "Enter a display name."
            return false
        }
        guard name.unicodeScalars.count <= signalLabelMaxUnicodeScalars else {
            enrollmentError = "Display name must be 100 characters or fewer."
            return false
        }
        let device = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !device.isEmpty else {
            enrollmentError = "Enter a device name."
            return false
        }
        guard device.unicodeScalars.count <= signalLabelMaxUnicodeScalars else {
            enrollmentError = "Device name must be 100 characters or fewer."
            return false
        }
        guard !isEnrolling else { return false }
        isEnrolling = true
        enrollmentError = nil
        defer { isEnrolling = false }

        let deviceToken: String?
        do {
            deviceToken = try await deviceCheckToken()
        } catch {
            deviceToken = nil
        }

        do {
            let enrollment = try await apiClient.createInstallation(
                displayName: name,
                deviceName: device,
                deviceCheckToken: deviceToken
            )
            try tokenStore.saveToken(enrollment.token)
            token = enrollment.token
            installation = enrollment.installation
            isEnrolled = true
            defaults.set(false, forKey: optOutKey)
            defaults.set(name, forKey: displayNameKey)
            return true
        } catch {
            enrollmentError = "Couldn’t enable contributions. Try again."
            return false
        }
    }

    public func refreshInstallation() async {
        guard let token, !isEnrolling else { return }
        installationRefreshGeneration += 1
        let generation = installationRefreshGeneration
        isEnrolling = true
        enrollmentError = nil
        defer { isEnrolling = false }
        do {
            let refreshed = try await apiClient.fetchInstallation(bearerToken: token)
            guard self.token == token, installationRefreshGeneration == generation else { return }
            installation = refreshed
        } catch ForumIndexAPIError.invalidBearerToken {
            guard self.token == token else { return }
            invalidateEnrollment(rejectedToken: token)
            enrollmentError = "Contribution access expired. Enroll again."
        } catch {
            guard self.token == token else { return }
            enrollmentError = "Couldn’t refresh contributor status."
        }
    }

    @discardableResult
    public func updateDeviceName(_ deviceName: String) async -> Bool {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            enrollmentError = "Enter a device name."
            return false
        }
        guard name.unicodeScalars.count <= signalLabelMaxUnicodeScalars else {
            enrollmentError = "Device name must be 100 characters or fewer."
            return false
        }
        guard let token, !isEnrolling else { return false }
        isEnrolling = true
        enrollmentError = nil
        defer { isEnrolling = false }
        do {
            let updated = try await apiClient.updateInstallation(deviceName: name, bearerToken: token)
            guard self.token == token else { return false }
            installation = updated
            return true
        } catch ForumIndexAPIError.invalidBearerToken {
            guard self.token == token else { return false }
            invalidateEnrollment(rejectedToken: token)
            enrollmentError = "Contribution access expired. Enroll again."
            return false
        } catch {
            guard self.token == token else { return false }
            enrollmentError = "Couldn’t update device name."
            return false
        }
    }

    public func enroll(inviteCode: String) async {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isEnrolling else {
            if code.isEmpty { enrollmentError = "Enter an invite code." }
            return
        }
        isEnrolling = true
        enrollmentError = nil
        defer { isEnrolling = false }
        do {
            let newToken = try await apiClient.enrollForSignals(inviteCode: code)
            try tokenStore.saveToken(newToken)
            token = newToken
            isEnrolled = true
            defaults.set(false, forKey: optOutKey)
        } catch {
            enrollmentError = "Couldn’t enable contributions. Check the code and try again."
        }
    }

    public func removeEnrollment() {
        guard let token else { return }
        do {
            _ = try tokenStore.deleteToken(matching: token)
            defaults.set(true, forKey: optOutKey)
            clearEnrollmentState()
            enrollmentError = nil
        } catch {
            enrollmentError = "Couldn’t remove contribution access."
        }
    }

    @discardableResult
    public func reportAction(topicID: Int, action: String, active: Bool) async -> String? {
        guard let token, !isEnrolling else { return nil }
        contributionError = nil

        let previous = actionReportTasks[topicID]
        let generation = actionReportGenerations[topicID, default: 0] + 1
        actionReportGenerations[topicID] = generation
        let task = Task { [apiClient] in
            _ = await previous?.value
            do {
                try await apiClient.reportAction(
                    topicID: topicID,
                    action: action,
                    active: active,
                    bearerToken: token
                )
                return ActionReportOutcome.success
            } catch ForumIndexAPIError.invalidBearerToken {
                return ActionReportOutcome.invalidBearerToken
            } catch {
                return ActionReportOutcome.failure
            }
        }
        actionReportTasks[topicID] = task
        let outcome = await task.value
        if case .success = outcome, action == "read", active, self.token == token {
            await refreshReadEligibility()
        }
        let errorMessage: String? = switch outcome {
        case .success: nil
        case .invalidBearerToken: "Contribution access expired."
        case .failure: "Couldn’t report this contribution."
        }
        guard self.token == token else { return errorMessage }
        if actionReportGenerations[topicID] == generation {
            actionReportTasks[topicID] = nil
            actionReportGenerations[topicID] = nil
        }

        switch outcome {
        case .success:
            break
        case .invalidBearerToken:
            invalidateEnrollment(rejectedToken: token)
            contributionError = "Contribution access expired."
        case .failure:
            contributionError = "Couldn’t report this contribution."
        }
        return errorMessage
    }

    public func submitForum(url: String) async -> String? {
        guard installation?.trusted == true, let token else { return "Trusted contributor access is required." }
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 1_000,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            return "Enter a valid HTTPS forum URL."
        }
        do {
            try await apiClient.submitForum(url: value, bearerToken: token)
            return nil
        } catch ForumIndexAPIError.invalidBearerToken {
            guard self.token == token else { return "Contributor access changed. Try again." }
            invalidateEnrollment(rejectedToken: token)
            return "Contributor access expired."
        } catch {
            return "Couldn’t submit this forum. Try again."
        }
    }

    public func submitFeedback(_ submission: FeedbackSubmission) async -> String? {
        guard submission.isValid else { return "Enter a message of up to 1,000 characters." }
        guard let credential = token, isEnrolled else {
            return "Enable contributions in Settings to send feedback. Your draft is saved."
        }
        do {
            try await apiClient.submitFeedback(submission, bearerToken: credential)
            return nil
        } catch ForumIndexAPIError.invalidBearerToken {
            if token == credential { invalidateEnrollment(rejectedToken: credential) }
            return "Your contributor access expired. Enable contributions in Settings to send feedback. Your draft is saved."
        } catch ForumIndexAPIError.httpStatus(let status) {
            switch status {
            case 404, 405, 501, 503:
                return "Feedback isn’t available yet. Your draft is saved; please try again later."
            case 429:
                return "Too many messages. Your draft is saved; please try again later."
            case 400, 413, 422:
                return "The message couldn’t be accepted. Please check it and try again."
            default:
                return "Couldn’t send feedback. Your draft is saved; please try again."
            }
        } catch {
            return "Couldn’t send feedback. Your draft is saved; please try again."
        }
    }

    public func optOut() async {
        guard let token, !isEnrolling else { return }
        isEnrolling = true
        contributionError = nil
        defer { isEnrolling = false }
        do {
            try await apiClient.revokeInstallation(bearerToken: token)
            guard self.token == token else { return }
            defaults.set(true, forKey: optOutKey)
            do {
                _ = try tokenStore.deleteToken(matching: token)
                clearEnrollmentState()
                enrollmentError = nil
            } catch {
                clearEnrollmentState()
                contributionError = "Access was revoked, but secure storage couldn’t be cleared."
            }
        } catch ForumIndexAPIError.invalidBearerToken {
            guard self.token == token else { return }
            defaults.set(true, forKey: optOutKey)
            invalidateEnrollment(rejectedToken: token)
        } catch {
            guard self.token == token else { return }
            contributionError = "Couldn’t opt out. Try again."
        }
    }

    public func signalValue(for topicID: Int) -> Int { values[topicID] ?? 0 }
    public func isUpdating(topicID: Int) -> Bool { updatingTopicIDs.contains(topicID) }
    public func signalError(for topicID: Int) -> String? { errors[topicID] }

    public func toggleSignal(topicID: Int, value: Int, deviceName: String? = nil) async {
        guard !updatingTopicIDs.contains(topicID), value == -1 || value == 1 else { return }
        if token == nil, let deviceName, !defaults.bool(forKey: optOutKey) {
            await enroll(displayName: "Anonymous", deviceName: deviceName)
        }
        guard let token else {
            errors[topicID] = enrollmentError
            return
        }
        let previous = signalValue(for: topicID)
        let next = previous == value ? 0 : value
        values[topicID] = next
        updatingTopicIDs.insert(topicID)
        errors[topicID] = nil
        defer { updatingTopicIDs.remove(topicID) }
        do {
            try await apiClient.setSignal(topicID: topicID, value: next, bearerToken: token)
            guard self.token == token else { return }
            if next == 0 { values.removeValue(forKey: topicID) }
            defaults.set(try? JSONEncoder().encode(values), forKey: valuesKey)
        } catch ForumIndexAPIError.invalidBearerToken {
            guard self.token == token else { return }
            invalidateEnrollment(rejectedToken: token)
            enrollmentError = "Contribution access expired. Enroll again."
        } catch {
            guard self.token == token else { return }
            if values[topicID] == next { values[topicID] = previous }
            errors[topicID] = "Couldn’t save your signal. Try again."
        }
    }

    private func invalidateEnrollment(rejectedToken: String) {
        _ = try? tokenStore.deleteToken(matching: rejectedToken)
        clearEnrollmentState()
    }

    private func clearEnrollmentState() {
        token = nil
        isEnrolled = false
        installation = nil
        values.removeAll()
        defaults.removeObject(forKey: valuesKey)
        errors.removeAll()
        contributionError = nil
    }
}
