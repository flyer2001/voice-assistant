import SwiftUI
import VoiceAssistant

/// First-launch sheet shown when the Keychain has no saved BACKEND_TOKEN.
/// User pastes the token, we store it in the Keychain, and the parent
/// view dismisses the sheet via `onSaved`.
struct OnboardingView: View {
    let tokenStore: any TokenStore
    let onSaved: (String) -> Void

    @State private var input: String = ""
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("Backend token")
                        .font(.title2.weight(.semibold))
                    Text("Paste your BACKEND_TOKEN. Stored in iOS Keychain — never logged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                TextField("token", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.body.monospaced())

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    save()
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("Set up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        do {
            try tokenStore.write(trimmed)
            onSaved(trimmed)
        } catch {
            errorMessage = "\(error)"
        }
    }
}

#Preview {
    OnboardingView(
        tokenStore: InMemoryTokenStore(),
        onSaved: { _ in }
    )
}
