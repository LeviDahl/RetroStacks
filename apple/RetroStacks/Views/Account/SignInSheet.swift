import SwiftUI

/// Presented from the Dashboard's account row. Two steps, matching
/// `AccountService.State`: send the link, then paste it back — no custom URL
/// scheme, so nothing about the Xcode target had to change to ship this (see
/// `SupabaseAuthClient`). Dismisses itself once signed in.
///
/// Deliberately kept "Confirm email" enabled server-side (Supabase Dashboard
/// → Authentication → Providers → Email) rather than turning it off for
/// convenience — real proof of inbox ownership before an account is usable.
/// The one thing that took real live-testing to confirm (2026-09-16): a
/// first-time address gets GoTrue's "Confirm your signup" email instead of a
/// magic-link one, but it's the *same* `/verify` link shape underneath
/// (`type=signup` vs `type=magiclink`), and `completeSignIn` already handles
/// either generically — so the existing paste-back flow needed no new code
/// path, just copy in `linkSection` that says so.
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account = AccountService.shared
    @State private var email = ""
    @State private var pastedLink = ""
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                switch account.state {
                case .signedOut, .sendingLink:
                    emailSection
                case .awaitingLink(let sentTo):
                    linkSection(sentTo: sentTo)
                case .signedIn:
                    EmptyView()
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.accentRed).font(.footnote)
                    }
                }
            }
            .navigationTitle("Sign In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        account.cancelSignIn()
                        dismiss()
                    }
                }
            }
            .onChange(of: account.state) { _, newValue in
                if newValue.isSignedIn { dismiss() }
            }
        }
    }

    private var emailSection: some View {
        Section {
            TextField("Email", text: $email)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.Account.emailField)
            Button {
                send()
            } label: {
                if working { ProgressView() } else { Text("Send Sign-In Link") }
            }
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || working)
            .accessibilityIdentifier(AccessibilityID.Account.sendLinkButton)
        } footer: {
            Text("No password — you’ll get a one-time link by email. Sync is optional; everything keeps working signed out.")
        }
    }

    private func linkSection(sentTo: String) -> some View {
        Section {
            Text("Check \(sentTo) for an email from us.")
            TextField("Paste the link here", text: $pastedLink)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.Account.pastedLinkField)
            Button {
                verify()
            } label: {
                if working { ProgressView() } else { Text("Verify") }
            }
            .disabled(pastedLink.trimmingCharacters(in: .whitespaces).isEmpty || working)
            .accessibilityIdentifier(AccessibilityID.Account.verifyButton)
        } footer: {
            // First-time addresses get GoTrue's "Confirm your signup" email
            // instead of a "magic link" one — same underlying verify link
            // either way (completeSignIn doesn't care which `type` it is),
            // but worth saying so nobody assumes the wrong email arrived.
            Text("The first time, it may say “Confirm your signup” instead of "
                + "“sign in” — that's normal, and works exactly the same way. "
                + "Copy the link from the email — you don’t need to open it — and paste it above.")
        }
    }

    private func send() {
        errorMessage = nil
        working = true
        Task {
            do {
                try await account.sendMagicLink(to: email.trimmingCharacters(in: .whitespaces))
            } catch {
                errorMessage = (error as? SupabaseAuthError)?.userMessage ?? error.localizedDescription
            }
            working = false
        }
    }

    private func verify() {
        errorMessage = nil
        working = true
        Task {
            do {
                try await account.completeSignIn(pastedLink: pastedLink)
            } catch {
                errorMessage = (error as? SupabaseAuthError)?.userMessage ?? error.localizedDescription
            }
            working = false
        }
    }
}

#Preview {
    SignInSheet()
}
