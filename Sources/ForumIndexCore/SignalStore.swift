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
    private let account: String

    public init(service: String = "com.musaraj.ForumIndex.signal-access", account: String = "signal-bearer-token") {
        self.service = service
        self.account = account
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
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}

@MainActor
public protocol PasskeyAuthorizing: AnyObject {
    func register(options: PasskeyRegistrationOptions) async throws -> PasskeyRegistrationCredential
    func authenticate(options: PasskeyAuthenticationOptions) async throws -> PasskeyAuthenticationCredential
}

@MainActor
@Observable
public final class SignalStore {
    public private(set) var isEnrolled = false
    public private(set) var isWorking = false
    public private(set) var accessRequestStatus: SignalAccessRequestStatus?
    public private(set) var accessError: String?

    private let apiClient: any SignalAPIClientProtocol
    private let tokenStore: any SignalTokenStore
    private let requestTokenStore: any SignalTokenStore
    private let passkeyAuthorizer: any PasskeyAuthorizing
    private let defaults: UserDefaults
    private let valuesKey = "topic-signal-values-v1"
    private var token: String?
    private var requestToken: String?
    private var values: [Int: Int] = [:]
    private var updatingTopicIDs: Set<Int> = []
    private var errors: [Int: String] = [:]

    public init(
        apiClient: any SignalAPIClientProtocol,
        tokenStore: any SignalTokenStore,
        requestTokenStore: any SignalTokenStore,
        passkeyAuthorizer: any PasskeyAuthorizing,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.requestTokenStore = requestTokenStore
        self.passkeyAuthorizer = passkeyAuthorizer
        self.defaults = defaults
        if let data = defaults.data(forKey: valuesKey) {
            values = (try? JSONDecoder().decode([Int: Int].self, from: data)) ?? [:]
        }
        do {
            token = try tokenStore.readToken()
            requestToken = try requestTokenStore.readToken()
            isEnrolled = token != nil
            if !isEnrolled, requestToken != nil { accessRequestStatus = .pending }
        } catch {
            accessError = "Couldn’t access secure storage."
        }
    }

    public func requestAccess(name: String, deviceModel: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceModel = deviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !deviceModel.isEmpty, !isWorking else {
            if name.isEmpty || deviceModel.isEmpty { accessError = "Enter your name and device model." }
            return
        }
        isWorking = true
        accessError = nil
        defer { isWorking = false }
        do {
            let request = try await apiClient.requestSignalAccess(name: name, deviceModel: deviceModel)
            guard let newRequestToken = request.requestToken else { throw ForumIndexAPIError.invalidResponse }
            try requestTokenStore.saveToken(newRequestToken)
            requestToken = newRequestToken
            accessRequestStatus = request.status
        } catch is CancellationError {
        } catch {
            accessError = "Couldn’t send the access request. Try again."
        }
    }

    public func refreshAccessRequest() async {
        guard let requestToken, !isEnrolled, !isWorking else { return }
        isWorking = true
        accessError = nil
        defer { isWorking = false }
        do {
            accessRequestStatus = try await apiClient.fetchSignalAccessRequest(requestToken: requestToken).status
        } catch is CancellationError {
        } catch {
            accessError = "Couldn’t check the request. Try again."
        }
    }

    public func enableWithPasskey() async {
        guard let requestToken, accessRequestStatus == .approved, !isWorking else { return }
        isWorking = true
        accessError = nil
        defer { isWorking = false }
        do {
            let options = try await apiClient.fetchPasskeyRegistrationOptions(requestToken: requestToken)
            let credential = try await passkeyAuthorizer.register(options: options)
            try storeBearer(try await apiClient.registerPasskey(credential, requestToken: requestToken))
            try? requestTokenStore.deleteToken()
            self.requestToken = nil
            accessRequestStatus = nil
        } catch is CancellationError {
        } catch {
            accessError = "Couldn’t enable access with your passkey. Try again."
        }
    }

    public func restoreWithPasskey() async {
        guard !isWorking else { return }
        isWorking = true
        accessError = nil
        defer { isWorking = false }
        do {
            let options = try await apiClient.fetchPasskeyAuthenticationOptions()
            let credential = try await passkeyAuthorizer.authenticate(options: options)
            try storeBearer(try await apiClient.authenticatePasskey(credential, ceremonyToken: options.ceremonyToken))
            try? requestTokenStore.deleteToken()
            requestToken = nil
            accessRequestStatus = nil
        } catch is CancellationError {
        } catch {
            accessError = "Couldn’t restore access with your passkey. Try again."
        }
    }

    public func removeAccess() {
        do {
            try tokenStore.deleteToken()
            token = nil
            isEnrolled = false
            values.removeAll()
            defaults.removeObject(forKey: valuesKey)
            errors.removeAll()
            accessError = nil
        } catch {
            accessError = "Couldn’t remove topic signal access."
        }
    }

    public func signalValue(for topicID: Int) -> Int { values[topicID] ?? 0 }
    public func isUpdating(topicID: Int) -> Bool { updatingTopicIDs.contains(topicID) }
    public func signalError(for topicID: Int) -> String? { errors[topicID] }

    public func toggleSignal(topicID: Int, value: Int) async {
        guard let bearerToken = token, !updatingTopicIDs.contains(topicID), value == -1 || value == 1 else { return }
        let previous = signalValue(for: topicID)
        let next = previous == value ? 0 : value
        values[topicID] = next
        updatingTopicIDs.insert(topicID)
        errors[topicID] = nil
        defer { updatingTopicIDs.remove(topicID) }
        do {
            try await apiClient.setSignal(topicID: topicID, value: next, bearerToken: bearerToken)
            if next == 0 { values.removeValue(forKey: topicID) }
            if values.isEmpty { defaults.removeObject(forKey: valuesKey) }
            else { defaults.set(try? JSONEncoder().encode(values), forKey: valuesKey) }
        } catch ForumIndexAPIError.httpStatus(401) {
            try? tokenStore.deleteToken()
            token = nil
            isEnrolled = false
            values.removeAll()
            defaults.removeObject(forKey: valuesKey)
            accessError = "Access expired. Restore access with your passkey in Settings."
            errors[topicID] = "Access expired. Restore it in Settings."
        } catch {
            if values[topicID] == next { values[topicID] = previous }
            errors[topicID] = "Couldn’t save your signal. Try again."
        }
    }

    private func storeBearer(_ newToken: String) throws {
        try tokenStore.saveToken(newToken)
        token = newToken
        isEnrolled = true
    }
}
