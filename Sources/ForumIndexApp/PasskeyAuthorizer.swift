import AuthenticationServices
import ForumIndexCore
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class SystemPasskeyAuthorizer: NSObject, PasskeyAuthorizing, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private static let relyingPartyID = "do3.musaraj.com"
    private var controller: ASAuthorizationController?
    private var registrationContinuation: CheckedContinuation<PasskeyRegistrationCredential, any Error>?
    private var authenticationContinuation: CheckedContinuation<PasskeyAuthenticationCredential, any Error>?

    func register(options: PasskeyRegistrationOptions) async throws -> PasskeyRegistrationCredential {
        guard options.rp.id == Self.relyingPartyID,
              registrationContinuation == nil, authenticationContinuation == nil else {
            throw PasskeyAuthorizerError.invalidOptions
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyID)
        let request = provider.createCredentialRegistrationRequest(
            challenge: try Data(base64URLEncoded: options.challenge),
            name: options.user.name,
            userID: try Data(base64URLEncoded: options.user.id)
        )
        request.displayName = options.user.displayName
        if #available(iOS 17.4, macOS 13.5, *) {
            request.excludedCredentials = try options.excludeCredentials.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: try Data(base64URLEncoded: $0.id))
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registrationContinuation = continuation
                perform(request)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func authenticate(options: PasskeyAuthenticationOptions) async throws -> PasskeyAuthenticationCredential {
        guard options.rpID == Self.relyingPartyID,
              registrationContinuation == nil, authenticationContinuation == nil else {
            throw PasskeyAuthorizerError.invalidOptions
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyID)
        let request = provider.createCredentialAssertionRequest(challenge: try Data(base64URLEncoded: options.challenge))
        request.allowedCredentials = try options.allowCredentials.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: try Data(base64URLEncoded: $0.id))
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                authenticationContinuation = continuation
                perform(request)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
#if os(iOS)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
#else
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
#endif
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        defer { self.controller = nil }
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            registrationContinuation?.resume(returning: PasskeyRegistrationCredential(
                id: credential.credentialID.base64URLEncodedString(),
                rawID: credential.credentialID.base64URLEncodedString(),
                response: .init(
                    clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                    attestationObject: credential.rawAttestationObject?.base64URLEncodedString() ?? ""
                )
            ))
            registrationContinuation = nil
        } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            authenticationContinuation?.resume(returning: PasskeyAuthenticationCredential(
                id: credential.credentialID.base64URLEncodedString(),
                rawID: credential.credentialID.base64URLEncodedString(),
                response: .init(
                    clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                    authenticatorData: credential.rawAuthenticatorData.base64URLEncodedString(),
                    signature: credential.signature.base64URLEncodedString(),
                    userHandle: credential.userID.isEmpty ? nil : credential.userID.base64URLEncodedString()
                )
            ))
            authenticationContinuation = nil
        } else {
            finish(throwing: PasskeyAuthorizerError.invalidCredential)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === self.controller else { return }
        self.controller = nil
        if (error as? ASAuthorizationError)?.code == .canceled { finish(throwing: CancellationError()) }
        else { finish(throwing: error) }
    }

    private func perform(_ request: ASAuthorizationRequest) {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    private func cancel() {
        controller?.cancel()
        controller = nil
        finish(throwing: CancellationError())
    }

    private func finish(throwing error: any Error) {
        registrationContinuation?.resume(throwing: error)
        authenticationContinuation?.resume(throwing: error)
        registrationContinuation = nil
        authenticationContinuation = nil
    }
}

private enum PasskeyAuthorizerError: Error { case invalidOptions, invalidCredential }

private extension Data {
    init(base64URLEncoded value: String) throws {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw PasskeyAuthorizerError.invalidOptions }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
