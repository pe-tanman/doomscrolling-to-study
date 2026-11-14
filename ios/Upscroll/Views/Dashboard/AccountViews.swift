import SwiftUI

/// Settings section: sign in by email, sync status, sign out, delete.
struct AccountSection: View {
    /// Opens the sign-in sheet. It's presented by the screen, not from inside the list row: a sheet owned by a
    /// Form row is dropped when the row re-renders (e.g. when the email link's error appears).
    var onSignIn: () -> Void
    @ObservedObject private var auth = SupabaseAuth.shared
    @ObservedObject private var sync = CloudSync.shared
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        if SupabaseAuth.isConfigured {
            Section {
                if let s = auth.session {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.icloud.fill").font(.title2).foregroundStyle(Brand.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.email ?? "Signed in").font(.subheadline.weight(.semibold))
                            statusText.font(.subheadline)
                        }
                    }
                    Button { Task { await sync.syncNow() } } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(sync.status == .syncing)
                    Button(role: .destructive) { confirmSignOut = true } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete account", systemImage: "trash") }
                        .font(.subheadline)
                } else {
                    Button { onSignIn() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
                            if !Rewards.shared.signInGiftClaimed {
                                (RewardIcon.gift.text() + Text(" ") + RewardText.signInGift()).font(.footnote).foregroundStyle(Brand.ink2)
                                    .accessibilityLabel("Sign-in gift: \(Rewards.signInGiftText)")
                            }
                        }
                    }
                    .accessibilityIdentifier("open-sign-in")
                }
                if let e = error ?? auth.linkError { Text(e).font(.subheadline).foregroundStyle(Brand.danger) }
            } header: { Text("Account") }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await CloudSync.shared.upload(); await auth.signOut() } }
            } message: { Text("Your progress is saved first and stays on this phone.") }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account and cloud copy", role: .destructive) {
                    Task {
                        do { try await auth.deleteAccount() } catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("This deletes your Upscroll account and its saved progress in the cloud. This phone keeps its copy.") }
        }
    }

    @ViewBuilder private var statusText: some View {
        switch sync.status {
        case .idle: Text("Not synced yet")
        case .syncing: Text("Syncing…")
        case .synced(let d): Text("Saved \(d.formatted(.relative(presentation: .named)))")
        case .failed(let m): Text("Couldn't sync: \(m)").foregroundStyle(Brand.danger)
        }
    }
}

/// Passwordless email sign-in, the common pattern (Slack, Notion, Medium): one screen for sign-in and sign-up,
/// a labelled email field that's focused and submits on Return, a primary button with its own spinner, inline
/// errors, then "Check your email" with Open Mail, an emailed code fallback and a resend with a cooldown.
struct SignInSheet: View {
    /// Legal pages. Set these once they exist; the footer shows links only for the ones that are set.
    static let termsURL: URL? = nil
    static let privacyURL: URL? = nil
    /// Supabase allows one email per address per 60 s.
    static let resendCooldown = 60

    private enum Step { case email, checkEmail }
    private enum Field { case email, code }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = SupabaseAuth.shared
    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var resendIn = 0
    @FocusState private var focus: Field?

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var emailValid: Bool {
        trimmedEmail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .email: emailStep
                    case .checkEmail: checkEmailStep
                    }
                    if let e = error ?? auth.linkError {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
                            Text(e).accessibilityIdentifier("sign-in-error")
                        }
                        .font(.subheadline).foregroundStyle(Brand.danger)
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .email {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button { withAnimation { step = .email; code = ""; error = nil }; focus = .email } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Back")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
        .onAppear {
            focus = .email
            #if DEBUG
            // UI tests: show "Check your email" without sending a real email.
            if ProcessInfo.processInfo.arguments.contains("-previewCheckEmail") { email = "learner@example.com"; step = .checkEmail }
            #endif
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in if signedIn { dismiss() } }   // the email link finished sign-in
        .task(id: resendIn > 0) {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }

    // MARK: Steps

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(icon: "person.crop.circle.badge.checkmark", title: "Sign in or create an account",
                   subtitle: "Keep your words, reviews and streak safe, and use them on any iPhone. No password needed.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focus, equals: .email)
                    .onSubmit { if emailValid { send() } }
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Brand.mist, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(focus == .email ? Brand.violet : Brand.line, lineWidth: focus == .email ? 2 : 1))
                    .accessibilityIdentifier("email-field")
                if !email.isEmpty && !emailValid && focus != .email {
                    Text("Enter a valid email address").font(.footnote).foregroundStyle(Brand.danger)
                }
            }
            if !Rewards.shared.signInGiftClaimed { signInGift }
            primaryButton("Continue with email", disabled: !emailValid, id: "send-code") { send() }
            legal
        }
    }

    /// The email has both: a code (type it here, or iOS fills it from Mail) and a sign-in link.
    private var checkEmailStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(icon: "envelope.badge.fill", title: "Check your email",
                   subtitle: "We sent a sign-in code and link to \(trimmedEmail).")
                .accessibilityIdentifier("check-email")
            CodeBoxes(code: $code, focused: $focus, field: .code)
                .onChange(of: code) { _, v in
                    let digits = String(v.filter(\.isNumber).prefix(SupabaseAuth.codeLength))
                    if digits != v { code = digits }
                    if digits.count == SupabaseAuth.codeLength && !busy { verify() }   // autofilled or typed: submit straight away
                }
            primaryButton("Verify code", disabled: code.count < SupabaseAuth.codeLength, id: "verify-code") { verify() }
            Button { if let u = URL(string: "message://") { UIApplication.shared.open(u) } } label: {
                Label("Open Mail to use the link", systemImage: "envelope.open.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.brandSecondary)
            .accessibilityIdentifier("open-mail")
            resendRow
        }
        .onAppear { focus = .code }
    }

    // MARK: Pieces

    /// The one-time gift for signing in.
    private var signInGift: some View {
        HStack(spacing: 12) {
            Image(systemName: RewardIcon.gift.symbol).font(.title2).foregroundStyle(RewardIcon.gift.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign-in gift").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                RewardText.signInGift().font(.subheadline).foregroundStyle(Brand.ink)
                    .accessibilityLabel(Rewards.signInGiftText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.sunSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sign-in-gift")
    }

    private func header(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Brand.violet)
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
            Text(subtitle).font(.body).foregroundStyle(Brand.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func primaryButton(_ title: String, disabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white) }
            }
            .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.brandPrimary)
        .disabled(disabled || busy)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityIdentifier(id)
    }

    private var resendRow: some View {
        HStack {
            Text("Didn't get it?").foregroundStyle(Brand.ink2)
            Button(resendIn > 0 ? "Resend in \(resendIn)s" : "Resend email") { send(advance: false) }
                .disabled(resendIn > 0 || busy)
                .fontWeight(.semibold)
                .accessibilityIdentifier("resend")
            Spacer()
            Button("Change email") { withAnimation { step = .email; code = ""; error = nil }; focus = .email }
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(Brand.violetDeep)
    }

    @ViewBuilder private var legal: some View {
        let links = [("Terms", Self.termsURL), ("Privacy Policy", Self.privacyURL)].compactMap { n, u in u.map { (n, $0) } }
        VStack(alignment: .leading, spacing: 4) {
            Text("We only use your email to sign you in and save your progress.")
            if !links.isEmpty {
                HStack(spacing: 4) {
                    Text("By continuing you agree to our")
                    ForEach(links, id: \.0) { n, u in Link(n, destination: u).fontWeight(.semibold) }
                }
            }
        }
        .font(.footnote).foregroundStyle(Brand.ink2)
    }

    // MARK: Actions

    private func send(advance: Bool = true) {
        guard emailValid else { return }
        run {
            try await SupabaseAuth.shared.sendEmailCode(trimmedEmail)
            resendIn = Self.resendCooldown
            if advance { withAnimation { step = .checkEmail } }
            focus = nil
        }
    }

    private func verify() {
        run { try await SupabaseAuth.shared.verifyEmailCode(trimmedEmail, code: code) }
    }

    /// Runs a sign-in step; on success syncs (download → merge → upload) and closes.
    private func run(_ step: @escaping () async throws -> Void) {
        busy = true; error = nil
        Task {
            do {
                try await step()
                if SupabaseAuth.shared.isSignedIn {
                    await CloudSync.shared.syncNow()
                    Rewards.shared.claimSignInGift()
                    dismiss()
                }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

/// Six digit boxes over one hidden field: one-time-code autofill and paste land in the field, the boxes mirror it.
struct CodeBoxes<F: Hashable>: View {
    @Binding var code: String
    var focused: FocusState<F?>.Binding
    var field: F? = nil

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .focused(focused, equals: field)
                .foregroundStyle(.clear).tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 58)   // the whole row is the tap target
                .accessibilityLabel("\(SupabaseAuth.codeLength)-digit code")
                .accessibilityIdentifier("code-field")
            HStack(spacing: 6) {
                ForEach(0..<SupabaseAuth.codeLength, id: \.self) { i in
                    let chars = Array(code)
                    let active = i == min(chars.count, SupabaseAuth.codeLength - 1)
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.ink)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Brand.mist, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(active ? Brand.violet : Brand.line, lineWidth: active ? 2 : 1))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
