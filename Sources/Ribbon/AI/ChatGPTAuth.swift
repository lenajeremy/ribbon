import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// The ChatGPT account Ribbon is signed in with, and its tokens. Kept in the keychain.
struct ChatGPTAccount: Codable {
    var email: String
    var subject: String
    var clientID: String
    var hostID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]
    var savedAt: Date

    /// The sign-in includes permission to use the ChatGPT plan, not only who you are.
    var canUsePlan: Bool { scopes.contains(ChatGPTAuth.planScope) }
}

enum ChatGPTAuthError: LocalizedError {
    case cancelled, portBusy, timedOut, denied, stateMismatch, clientMismatch, invalidToken(String), signInNeeded, server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .portBusy: "Ribbon couldn't wait for the browser: another app is signing in to ChatGPT right now. Try again in a minute."
        case .timedOut: "Sign-in timed out. Try again, and finish signing in in your browser."
        case .denied: "Sign-in was declined in the browser."
        case .stateMismatch, .clientMismatch: "The browser sent back a sign-in Ribbon didn't start. Try again."
        case .invalidToken(let why): "ChatGPT's sign-in couldn't be verified (\(why)). Try again."
        case .signInNeeded: "Your ChatGPT sign-in has expired or was disconnected. Sign in again in Settings › AI."
        case .server(let message): message
        }
    }
}

/// Sign in with ChatGPT for open-source, locally run apps (OpenAI's plan-sharing preview), so Ribbon's AI can use the
/// person's ChatGPT plan instead of an API key. The browser signs in at auth.openai.com with PKCE and comes back to a
/// listener on 127.0.0.1. The first sign-in registers Ribbon for this user and returns its own client ID, which later
/// sign-ins reuse. Tokens live in the keychain; the access token lasts an hour and is renewed with the refresh token.
/// https://developers.openai.com/siwc/token-sharing-open-source
final class ChatGPTAuth: @unchecked Sendable {
    static let planScope = "chatgpt.tokens.use.direct"
    static let usageSettings = URL(string: "https://chatgpt.com/#settings")!
    private static let issuer = "https://auth.openai.com"
    private static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private static let configurationURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    private static let resource = "https://api.openai.com/v1"
    private static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    /// A first registration must come back on this port; returning sign-ins may use any.
    private static let firstRegistrationPort: UInt16 = 1455

    private let lock = NSLock()
    private var current: ChatGPTAccount?
    private var refreshing: Task<ChatGPTAccount, Error>?
    private var callback: LoopbackCallback?
    private let defaults = UserDefaults.standard
    private let session: URLSession

    /// Loads the saved sign-in, or starts from `account` (for tests).
    init(account: ChatGPTAccount? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        current = account ?? Self.loadAccount()
    }

    var account: ChatGPTAccount? { lock.withLock { current } }
    var canUsePlan: Bool { account?.canUsePlan == true }

    // MARK: Signing in

    /// Opens the browser to sign in and waits up to five minutes for it to come back.
    func signIn() async throws -> ChatGPTAccount {
        let savedClient = defaults.string(forKey: "chatgptClientID")
        let previous = account
        let state = Self.random(), nonce = Self.random(), verifier = Self.random(bytes: 32)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))

        let listener = try LoopbackCallback(port: savedClient == nil ? Self.firstRegistrationPort : 0)
        lock.withLock { callback = listener }
        defer { lock.withLock { callback = nil } }
        let port = try await listener.start()
        let redirect = "http://127.0.0.1:\(port)/auth/callback"

        let url = Self.authorizationURL(savedClient: savedClient, hostID: hostID, previous: previous, redirect: redirect,
                                        state: state, nonce: nonce, challenge: challenge)
        await MainActor.run { _ = NSWorkspace.shared.open(url) }

        let reply = try await listener.wait(timeout: 300)
        if reply["error"] != nil { throw ChatGPTAuthError.denied }
        guard reply["state"] == state else { throw ChatGPTAuthError.stateMismatch }
        guard let code = reply["code"], !code.isEmpty else { throw ChatGPTAuthError.denied }
        if let issued = reply["client_id"], let savedClient, issued != savedClient { throw ChatGPTAuthError.clientMismatch }
        guard let clientID = reply["client_id"] ?? savedClient else { throw ChatGPTAuthError.invalidToken("no client ID") }

        let tokens = try await postForm([
            "grant_type": "authorization_code", "client_id": clientID, "code": code, "code_verifier": verifier,
            "redirect_uri": redirect, "resource": Self.resource,
        ])
        let account = try makeAccount(tokens, clientID: clientID, nonce: nonce, fallbackScopes: reply["scope"])
        defaults.set(clientID, forKey: "chatgptClientID")
        save(account)
        logLine("Signed in with ChatGPT as \(account.email)\(account.canUsePlan ? "" : " (plan usage not allowed)")")
        return account
    }

    /// Where the browser goes to sign in. A first registration names Ribbon and gets a client ID of its own;
    /// later sign-ins reuse it and hint at the saved account.
    static func authorizationURL(savedClient: String?, hostID: String, previous: ChatGPTAccount?, redirect: String,
                                 state: String, nonce: String, challenge: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "client_id", value: savedClient ?? "dynamic_agent_client")]
        if savedClient == nil { items.append(URLQueryItem(name: "agent_name_hint", value: "Ribbon")) }
        items.append(URLQueryItem(name: "ext_agent_host_id", value: hostID))
        if let previous {
            items.append(URLQueryItem(name: "id_token_hint", value: previous.idToken))
            items.append(URLQueryItem(name: "login_hint", value: previous.email))
        }
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        components.queryItems = items
        // "@" and "+" mean something in a query; encode them like the other reserved characters.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "@", with: "%40").replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    func cancelSignIn() {
        lock.withLock { callback }?.cancel()
    }

    /// Revokes the sign-in and forgets the tokens. Returns false if OpenAI couldn't be told, in which case the app
    /// can still be disconnected in ChatGPT's settings.
    @discardableResult func signOut() async -> Bool {
        guard let account else { return true }
        var revoked = false
        if let endpoint = await revocationEndpoint() {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": account.refreshToken, "token_type_hint": "refresh_token", "client_id": account.clientID])
            if let (_, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 {
                revoked = true
            }
        }
        save(nil)
        logLine("Signed out of ChatGPT\(revoked ? "" : " (couldn't reach OpenAI to revoke the sign-in)")")
        return revoked
    }

    // MARK: Tokens

    /// A current access token, renewed first when it's about to expire.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let account else { throw ChatGPTAuthError.signInNeeded }
        if !forceRefresh && account.expiresAt.timeIntervalSinceNow > 120 { return account.accessToken }
        return try await refresh().accessToken
    }

    /// One renewal at a time: refresh tokens are replaced on every use.
    private func refresh() async throws -> ChatGPTAccount {
        let task: Task<ChatGPTAccount, Error> = lock.withLock {
            if let refreshing { return refreshing }
            let task = Task { [self] in
                defer { lock.withLock { refreshing = nil } }
                return try await performRefresh()
            }
            refreshing = task
            return task
        }
        return try await task.value
    }

    private func performRefresh() async throws -> ChatGPTAccount {
        guard var account else { throw ChatGPTAuthError.signInNeeded }
        let tokens: [String: Any]
        do {
            tokens = try await postForm([
                "grant_type": "refresh_token", "client_id": account.clientID, "refresh_token": account.refreshToken,
                "resource": Self.resource,
            ])
        } catch let error as ChatGPTAuthError {
            if case .signInNeeded = error { save(nil) }
            throw error
        }
        guard let access = tokens["access_token"] as? String else { throw ChatGPTAuthError.invalidToken("no access token") }
        account.accessToken = access
        if let refresh = tokens["refresh_token"] as? String { account.refreshToken = refresh }
        if let id = tokens["id_token"] as? String { account.idToken = id }
        account.expiresAt = Date().addingTimeInterval(Self.seconds(tokens["expires_in"]) ?? 3600)
        if let scope = tokens["scope"] as? String { account.scopes = scope.split(separator: " ").map(String.init) }
        account.savedAt = Date()
        save(account)
        return account
    }

    /// Checks the ID token and builds the account. The token comes straight from OpenAI's token endpoint over TLS,
    /// so its issuer, audience, expiry and nonce are checked here and TLS stands in for the signature check
    /// (OpenID Connect Core, section 3.1.3.7).
    private func makeAccount(_ tokens: [String: Any], clientID: String, nonce: String, fallbackScopes: String?) throws -> ChatGPTAccount {
        guard let access = tokens["access_token"] as? String, let refresh = tokens["refresh_token"] as? String,
              let idToken = tokens["id_token"] as? String else { throw ChatGPTAuthError.invalidToken("missing tokens") }
        let claims = try Self.claims(of: idToken)
        guard claims["iss"] as? String == Self.issuer else { throw ChatGPTAuthError.invalidToken("issuer") }
        let audience = (claims["aud"] as? String).map { [$0] } ?? (claims["aud"] as? [String] ?? [])
        guard audience.contains(clientID) else { throw ChatGPTAuthError.invalidToken("audience") }
        guard let expiry = Self.seconds(claims["exp"]), Date(timeIntervalSince1970: expiry) > Date().addingTimeInterval(-60) else {
            throw ChatGPTAuthError.invalidToken("expired")
        }
        guard claims["nonce"] as? String == nonce else { throw ChatGPTAuthError.invalidToken("nonce") }
        guard let subject = claims["sub"] as? String, !subject.isEmpty else { throw ChatGPTAuthError.invalidToken("subject") }
        let scopes = (tokens["scope"] as? String ?? fallbackScopes ?? "").split(separator: " ").map(String.init)
        return ChatGPTAccount(
            email: claims["email"] as? String ?? "your ChatGPT account", subject: subject, clientID: clientID, hostID: hostID,
            idToken: idToken, accessToken: access, refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(Self.seconds(tokens["expires_in"]) ?? 3600), scopes: scopes, savedAt: Date())
    }

    // MARK: Plumbing

    private var hostID: String {
        if let id = defaults.string(forKey: "chatgptHostID") { return id }
        let id = "urn:uuid:" + UUID().uuidString.lowercased()
        defaults.set(id, forKey: "chatgptHostID")
        return id
    }

    private static let refreshErrors: Set<String> = ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
                                                     "refresh_token_invalidated", "refresh_token_reused"]

    private func postForm(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form(fields)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let code = json["error"] as? String ?? (json["error"] as? [String: Any])?["code"] as? String ?? ""
            if Self.refreshErrors.contains(code) { throw ChatGPTAuthError.signInNeeded }
            let message = json["error_description"] as? String ?? (json["error"] as? [String: Any])?["message"] as? String ?? code
            throw ChatGPTAuthError.server("ChatGPT sign-in failed (HTTP \(status))\(message.isEmpty ? "" : ": \(message)")")
        }
        return json
    }

    private func revocationEndpoint() async -> URL? {
        guard let (data, _) = try? await session.data(from: Self.configurationURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoint = json["revocation_endpoint"] as? String else { return nil }
        return URL(string: endpoint)
    }

    private func save(_ account: ChatGPTAccount?) {
        lock.withLock { current = account }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Ribbon",
                                   kSecAttrAccount as String: "ChatGPT sign-in"]
        SecItemDelete(base as CFDictionary)
        guard let account, let data = try? JSONEncoder().encode(account) else { return }
        var item = base
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func loadAccount() -> ChatGPTAccount? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Ribbon",
                                    kSecAttrAccount as String: "ChatGPT sign-in", kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ChatGPTAccount.self, from: data)
    }

    static func claims(of jwt: String) throws -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw ChatGPTAuthError.invalidToken("malformed") }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ChatGPTAuthError.invalidToken("malformed") }
        return claims
    }

    private static func seconds(_ value: Any?) -> TimeInterval? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    static func random(bytes: Int = 24) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64url(data)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Waits for the browser to come back to http://127.0.0.1:<port>/auth/callback with the sign-in result, and shows
/// a short page there. Listens on the loopback address only.
final class LoopbackCallback: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "Ribbon.ChatGPTCallback")
    private let lock = NSLock()
    private var result: Result<[String: String], Error>?
    private var waiter: CheckedContinuation<[String: String], Error>?
    private var starting: CheckedContinuation<UInt16, Error>?

    init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            lock.withLock { starting = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                let waiting = self.lock.withLock { () -> CheckedContinuation<UInt16, Error>? in
                    defer { if case .ready = state { self.starting = nil } else if case .failed = state { self.starting = nil } }
                    return self.starting
                }
                switch state {
                case .ready:
                    waiting?.resume(returning: self.listener.port?.rawValue ?? 0)
                case .failed:
                    if let waiting { waiting.resume(throwing: ChatGPTAuthError.portBusy) } else { self.finish(.failure(ChatGPTAuthError.portBusy)) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    /// The callback's query parameters, once the browser arrives.
    func wait(timeout: TimeInterval) async throws -> [String: String] {
        let timer = Task {
            do {
                try await Task.sleep(for: .seconds(timeout))
                finish(.failure(ChatGPTAuthError.timedOut))
            } catch {}
        }
        defer {
            timer.cancel()
            listener.cancel()
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let result { continuation.resume(with: result) } else { waiter = continuation }
            }
        }
    }

    func cancel() { finish(.failure(ChatGPTAuthError.cancelled)) }

    private func finish(_ outcome: Result<[String: String], Error>) {
        lock.withLock {
            guard result == nil else { return }
            result = outcome
            waiter?.resume(with: outcome)
            waiter = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let url = URLComponents(string: "http://127.0.0.1" + parts[1]), url.path == "/auth/callback" else {
                self.reply(connection, status: "404 Not Found", page: "")
                return
            }
            var parameters: [String: String] = [:]
            for item in url.queryItems ?? [] { parameters[item.name] = item.value ?? "" }
            let succeeded = parameters["error"] == nil && parameters["code"] != nil
            self.reply(connection, status: "200 OK", page: Self.page(succeeded))
            self.finish(.success(parameters))
        }
    }

    private func reply(_ connection: NWConnection, status: String, page: String) {
        let body = Data(page.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func page(_ succeeded: Bool) -> String {
        let title = succeeded ? "You're signed in to Ribbon" : "Sign-in didn't finish"
        let text = succeeded ? "Ribbon can now use your ChatGPT plan. You can close this tab and go back to Ribbon."
                             : "You can close this tab and try again from Ribbon's settings."
        return """
            <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title>
            <style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;\
            background:#fff;color:#0d0d0d}@media(prefers-color-scheme:dark){body{background:#212121;color:#ececec}}\
            main{max-width:420px;text-align:center}h1{font-size:22px;font-weight:600}p{color:#8f8f8f}</style></head>
            <body><main><h1>\(title)</h1><p>\(text)</p></main></body></html>
            """
    }
}
