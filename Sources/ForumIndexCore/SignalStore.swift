import Foundation
import Observation
import Security

public protocol SignalTokenStore: Sendable {
    func readToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

public enum SignalTokenStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
}

public final class KeychainSignalTokenStore: SignalTokenStore, @unchecked Sendable {
    private let service: String
    private let account = "signal-bearer-token"

    public init(service: String = "com.musaraj.ForumIndex.signal-enrollment") {
        self.service = service
    }

    public func readToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SignalTokenStoreError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw SignalTokenStoreError.keychain(errSecDecode)
        }
        return token
    }

    public func saveToken(_ token: String) throws {
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
    }

    public func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SignalTokenStoreError.keychain(status)
        }
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
    public private(set) var isEnrolled = false
    public private(set) var isEnrolling = false
    public private(set) var enrollmentError: String?

    private let apiClient: any SignalAPIClientProtocol
    private let tokenStore: any SignalTokenStore
    private let defaults: UserDefaults
    private let valuesKey = "topic-signal-values-v1"
    private var token: String?
    private var values: [Int: Int] = [:]
    private var updatingTopicIDs: Set<Int> = []
    private var errors: [Int: String] = [:]

    public init(
        apiClient: any SignalAPIClientProtocol,
        tokenStore: any SignalTokenStore,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.defaults = defaults
        if let data = defaults.data(forKey: valuesKey) {
            values = (try? JSONDecoder().decode([Int: Int].self, from: data)) ?? [:]
        }
        do {
            token = try tokenStore.readToken()
            isEnrolled = token != nil
        } catch {
            enrollmentError = "Couldn’t access secure storage."
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
        } catch {
            enrollmentError = "Couldn’t enable topic signals. Check the code and try again."
        }
    }

    public func removeEnrollment() {
        do {
            try tokenStore.deleteToken()
            token = nil
            isEnrolled = false
            values.removeAll()
            defaults.removeObject(forKey: valuesKey)
            errors.removeAll()
            enrollmentError = nil
        } catch {
            enrollmentError = "Couldn’t remove topic signal access."
        }
    }

    public func signalValue(for topicID: Int) -> Int { values[topicID] ?? 0 }
    public func isUpdating(topicID: Int) -> Bool { updatingTopicIDs.contains(topicID) }
    public func signalError(for topicID: Int) -> String? { errors[topicID] }

    public func toggleSignal(topicID: Int, value: Int) async {
        guard let token, !updatingTopicIDs.contains(topicID), value == -1 || value == 1 else { return }
        let previous = signalValue(for: topicID)
        let next = previous == value ? 0 : value
        values[topicID] = next
        updatingTopicIDs.insert(topicID)
        errors[topicID] = nil
        defer { updatingTopicIDs.remove(topicID) }
        do {
            try await apiClient.setSignal(topicID: topicID, value: next, bearerToken: token)
            if next == 0 { values.removeValue(forKey: topicID) }
            defaults.set(try? JSONEncoder().encode(values), forKey: valuesKey)
        } catch {
            if values[topicID] == next { values[topicID] = previous }
            errors[topicID] = "Couldn’t save your signal. Try again."
        }
    }
}
