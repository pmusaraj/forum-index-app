import ForumIndexCore
import SwiftUI

struct FeedbackView: View {
    @Bindable var signals: SignalStore
    @AppStorage("feedback-message-v1") private var message = ""
    @AppStorage("feedback-request-id-v1") private var requestID = ""
    @FocusState private var messageFocused: Bool
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private var messageCount: Int { message.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count }

    var body: some View {
        Form {
            if didSend {
                Section {
                    Label("Thanks for your feedback", systemImage: "checkmark.circle")
                        .font(.headline)
                    Text("Your message has been sent to the app admins.")
                    Button("Send more feedback") { didSend = false }
                }
            } else {
                Section {
                    TextField("What would you like us to know?", text: $message, axis: .vertical)
                        .lineLimit(6...12)
                        .focused($messageFocused)
                        .accessibilityLabel("Feedback message")
                        .accessibilityIdentifier("feedback-message")
                    Text("\(messageCount) / \(FeedbackSubmission.messageLimit)")
                        .font(.caption)
                        .foregroundStyle(messageCount > FeedbackSubmission.messageLimit ? Color.red : Color.secondary)
                } footer: {
                    Text("Feedback is linked to your contributor profile and sent to app admins with your app and OS versions.")
                }
                .disabled(isSending)

                Section {
                    Button(action: send) {
                        if isSending {
                            HStack {
                                ProgressView()
                                Text("Sending…")
                            }
                        } else {
                            Text("Send feedback")
                        }
                    }
                    .disabled(!signals.isEnrolled || isSending || messageCount == 0 || messageCount > FeedbackSubmission.messageLimit)
                    .accessibilityIdentifier("send-feedback")
                    if !signals.isEnrolled {
                        Text("Enable contributions in Settings to send feedback. Your draft is saved.")
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("feedback-error")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Feedback")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { messageFocused = false }
            }
        }
#endif
#if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_FEEDBACK"] == "1" {
                message = ""
                requestID = ""
            }
        }
#endif
        .onChange(of: message) { _, _ in draftChanged() }
    }

    private func draftChanged() {
        requestID = UUID().uuidString
        errorMessage = nil
    }

    private func send() {
        guard signals.isEnrolled, !isSending, messageCount > 0, messageCount <= FeedbackSubmission.messageLimit else { return }
        let id = UUID(uuidString: requestID) ?? UUID()
        requestID = id.uuidString
#if os(iOS)
        let platform = "ios"
#else
        let platform = "macos"
#endif
        let submission = FeedbackSubmission(
            requestID: id, message: message,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            platform: platform, osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        messageFocused = false
        isSending = true
        errorMessage = nil
        Task {
            let error = await signals.submitFeedback(submission)
            isSending = false
            if let error {
                errorMessage = error
            } else {
                // Another window may have edited the shared draft while this request was in flight.
                if requestID == id.uuidString {
                    message = ""
                    requestID = UUID().uuidString
                }
                didSend = true
            }
        }
    }
}
