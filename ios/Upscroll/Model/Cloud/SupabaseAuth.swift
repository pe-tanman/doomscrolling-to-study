import Foundation
import Security
import CryptoKit
import CommonCrypto

/// Minimal Supabase client over REST (no SDK): email sign-in (link or code), token refresh,
/// and authenticated PostgREST calls. The session lives in the Keychain, never in UserDefaults.
@MainActor
final class SupabaseAuth: ObservableObject {
    static let shared = SupabaseAuth()

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userId: String
        var email: String?
    }

    enum AuthError: LocalizedError {
        case notConfigured, server(String), noSession
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Cloud sign-in isn't set up in this build yet."
            case .server(let m): return m
            case .noSession: return "Please sign in again."
            }
        }
    }

    @Published private(set) var session: Session?
    /// Why the last email link failed (expired, already used…), shown in Settings and the sign-in sheet.
    @Published var linkError: String?
    var isSignedIn: Bool { session != nil }

    /// Project URL and anon (publishable) key from Info.plist (set via Secrets.xcconfig).
    /// xcconfig can't hold "//", so SUPABASE_HOST is the bare host, e.g. abcd.supabase.co.
    nonisolated static let baseURL: URL? = {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String,
              !host.isEmpty, !host.hasPrefix("$(") else { return nil }
        return URL(string: host.hasPrefix("http") ? host : "https://\(host)")
    }()
    nonisolated static let anonKey: String? = {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !k.isEmpty, !k.hasPrefix("$(") else { return nil }
        return k
    }()
    static var isConfigured: Bool { baseURL != nil && anonKey != nil }

    private init() { session = Keychain.load() }

    // MARK: Email link (default Supabase email) or one-time code

    static let redirectURL = "upscroll://auth-callback"
    /// Digits in the emailed code. Must match Supabase → Authentication → Email → "Email OTP Length" (6).
    static let codeLength = 6
    private static let verifierKey = "auth.pkceVerifier"

    /// Sends the sign-in email. Uses PKCE: the link only works with the secret kept on this phone,
    /// so another app that registers the same URL scheme can't use an intercepted link.
    func sendEmailCode(_ email: String) async throws {
        linkError = nil
        #if DEBUG
        // UI tests: the server's "couldn't send the email" answer, without sending one.
        if ProcessInfo.processInfo.arguments.contains("-fakeSendFailure") {
            throw AuthError.server(Self.friendly(status: 500, message: "Error sending magic link email", errorCode: "unexpected_failure"))
        }
        #endif
        let verifier = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        UserDefaults.standard.set(verifier, forKey: Self.verifierKey)   // survives the trip to Mail
        let redirect = Self.redirectURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        _ = try await auth("otp?redirect_to=\(redirect)",
                           body: ["email": email, "create_user": true, "code_challenge": challenge, "code_challenge_method": "s256"])
    }

    /// The email link came back: upscroll://auth-callback?code=… (or an error).
    func handleCallback(_ url: URL) async {
        guard url.scheme == "upscroll", url.host == "auth-callback" else { return }
        // Errors arrive in the query or the #fragment.
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let f = url.fragment { parts += URLComponents(string: "?\(f)")?.queryItems ?? [] }
        let value = { (name: String) in parts.first { $0.name == name }?.value }
        if let problem = value("error_description") ?? value("error") {
            linkError = problem.replacingOccurrences(of: "+", with: " ")
            return
        }
        guard let code = value("code"), let verifier = UserDefaults.standard.string(forKey: Self.verifierKey) else {
            linkError = "That sign-in link can't be used on this phone. Request a new one here."
            return
        }
        do {
            let json = try await auth("token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
            try adopt(json)
            UserDefaults.standard.removeObject(forKey: Self.verifierKey)
            linkError = nil
            await CloudSync.shared.syncNow()
            Rewards.shared.claimSignInGift()
        } catch { linkError = error.localizedDescription }
    }

    /// The 6-digit code from the email. The email was requested with PKCE (so its link only works on this phone),
    /// and Supabase then stores the token as "pkce_" + hash, which a plain code check never matches
    /// ("token has expired or is invalid"). So: the plain check first, then the same code in its stored PKCE form
    /// (`token_hash` = "pkce_" + hex SHA-224 of email + code, Supabase's own token hash). Either way the server
    /// still checks the code; nothing is weakened.
    func verifyEmailCode(_ email: String, code: String) async throws {
        do {
            let json = try await auth("verify", body: ["type": "email", "email": email, "token": code])
            try adopt(json)
        } catch {
            let hash = "pkce_" + Self.tokenHash(email: email, code: code)
            var lastError = error
            for type in ["email", "magiclink"] {   // new and returning users store the token differently
                do {
                    let json = try await auth("verify", body: ["type": type, "token_hash": hash])
                    try adopt(json)
                    UserDefaults.standard.removeObject(forKey: Self.verifierKey)
                    return
                } catch { lastError = error }
            }
            throw lastError
        }
    }

    /// Supabase's token hash: lowercase hex SHA-224 of email + code.
    nonisolated static func tokenHash(email: String, code: String) -> String {
        let data = Array((email + code).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
        CC_SHA224(data, CC_LONG(data.count), &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Session

    /// A valid access token, refreshing it when it's about to expire.
    func accessToken() async throws -> String {
        guard var s = session else { throw AuthError.noSession }
        if s.expiresAt.timeIntervalSinceNow < 60 {
            let json = try await auth("token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken])
            try adopt(json)
            guard let fresh = session else { throw AuthError.noSession }
            s = fresh
        }
        return s.accessToken
    }

    func signOut() async {
        if let s = session { _ = try? await auth("logout", body: [:], bearer: s.accessToken) }
        session = nil
        Keychain.delete()
    }

    /// Deletes the Supabase account (and its progress row, by cascade). Local data stays on the phone.
    func deleteAccount() async throws {
        let token = try await accessToken()
        _ = try await rest("rpc/delete_my_account", method: "POST", body: Data("{}".utf8), token: token)
        session = nil
        Keychain.delete()
    }

    private func adopt(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any], let id = user["id"] as? String else {
            throw AuthError.server("Unexpected sign-in response.")
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let s = Session(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn),
                        userId: id, email: user["email"] as? String)
        session = s
        Keychain.save(s)
    }

    // MARK: HTTP

    private func auth(_ path: String, body: [String: Any], bearer: String? = nil) async throws -> [String: Any] {
        guard let base = Self.baseURL, let key = Self.anonKey else { throw AuthError.notConfigured }
        var r = URLRequest(url: URL(string: "auth/v1/\(path)", relativeTo: base)!)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { r.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else {
            let msg = (json["msg"] ?? json["error_description"] ?? json["message"] ?? json["error"]) as? String
            throw AuthError.server(Self.friendly(status: code, message: msg, errorCode: json["error_code"] as? String))
        }
        return json
    }

    /// Plain-language sign-in errors (the server's own text is often "Error sending magic link email").
    static func friendly(status: Int, message: String?, errorCode: String?) -> String {
        let m = (message ?? "").lowercased()
        if status == 429 || errorCode == "over_email_send_rate_limit" || m.contains("rate limit") || m.contains("only request this after") {
            return "Too many sign-in emails were requested. Please wait a minute and try again."
        }
        if m.contains("sending") || m.contains("send email") || (status >= 500 && m.contains("mail")) {
            return "We couldn't send the sign-in email right now. Please try again in a few minutes."
        }
        if status >= 500 { return "Something went wrong on our side. Please try again in a few minutes." }
        if errorCode == "otp_expired" || m.contains("expired") || (m.contains("invalid") && m.contains("token")) {
            return "That code has expired or is wrong. Request a new email and try again."
        }
        if errorCode == "email_address_invalid" || (m.contains("invalid") && m.contains("email")) {
            return "That email address can't be used. Check it and try again."
        }
        return message ?? "Sign-in failed (\(status)). Please try again."
    }

    /// Authenticated PostgREST call (row-level security uses the user's token).
    func rest(_ path: String, method: String, body: Data? = nil, token: String,
              headers: [String: String] = [:]) async throws -> Data {
        guard let base = Self.baseURL, let key = Self.anonKey else { throw AuthError.notConfigured }
        var r = URLRequest(url: URL(string: "rest/v1/\(path)", relativeTo: base)!)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        r.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.server((json?["message"] as? String) ?? "Cloud request failed (\(code)).")
        }
        return data
    }
}

/// Keychain storage for the session (survives reinstall-free relaunches; not synced to iCloud).
private enum Keychain {
    static let account = "supabase.session"
    static let service = "com.upscroll.app.auth"

    static func save(_ s: SupabaseAuth.Session) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> SupabaseAuth.Session? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseAuth.Session.self, from: data)
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
