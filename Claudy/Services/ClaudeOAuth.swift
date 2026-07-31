import AppKit
import CryptoKit
import Foundation
import Network

enum OAuthError: LocalizedError {
    case timedOut
    case stateMismatch
    case malformedCode
    case exchangeFailed(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timedOut: "La connexion a expiré — réessaie."
        case .stateMismatch: "Réponse d'autorisation inattendue (state) — réessaie."
        case .malformedCode: "Code invalide — colle exactement ce que la page affiche (code#state)."
        case .exchangeFailed(let status): "Échange du code refusé (HTTP \(status))."
        case .cancelled: "Connexion annulée."
        }
    }
}

/// Flux OAuth *authorization code + PKCE* avec le client public de Claude Code.
///
/// Claudy obtient ainsi **son propre jeton** : plus aucune lecture du trousseau de Claude
/// Code, donc plus jamais le dialogue macOS « informations confidentielles ». La session
/// est indépendante — la rotation des jetons de l'un n'affecte pas l'autre.
///
/// Deux modes de capture du code :
/// 1. *Loopback* — un mini serveur HTTP local sur `localhost:54545` reçoit la redirection
///    du navigateur. Zéro manipulation.
/// 2. *Collage manuel* — repli quand le port est pris : la page affiche `code#state`,
///    l'utilisateur le colle dans la carte de connexion.
@MainActor
final class ClaudeOAuth {

    enum Mode { case loopback, manual }

    private static let authorizeBase = "https://claude.ai/oauth/authorize"
    private static let manualRedirect = "https://console.anthropic.com/oauth/code/callback"
    private static let loopbackPort: UInt16 = 54545
    private static let scopes = "org:create_api_key user:profile user:inference"

    private var verifier = ""
    private var state = ""
    private var redirectURI = ""
    private var server: LoopbackServer?

    /// Génère verifier/state, choisit le mode, ouvre le navigateur.
    func begin() -> Mode {
        verifier = Self.randomURLSafe(64)
        state = Self.randomURLSafe(32)

        if LoopbackServer.portAvailable(Self.loopbackPort),
           let server = try? LoopbackServer(port: Self.loopbackPort) {
            self.server = server
            redirectURI = "http://localhost:\(Self.loopbackPort)/callback"
            NSWorkspace.shared.open(authorizeURL())
            return .loopback
        }

        server = nil
        redirectURI = Self.manualRedirect
        NSWorkspace.shared.open(authorizeURL())
        return .manual
    }

    /// Mode loopback : attend la redirection du navigateur puis échange le code.
    func awaitLoopbackCode() async throws -> OAuthCredentials {
        guard let server else { throw OAuthError.cancelled }
        defer { self.server = nil }
        let code = try await server.waitForCode(expectedState: state, timeout: 300)
        return try await Self.exchange(code: code, state: state,
                                       verifier: verifier, redirectURI: redirectURI)
    }

    /// Mode manuel : la page affiche `code#state`, l'utilisateur le colle tel quel.
    func redeemManualCode(_ pasted: String) async throws -> OAuthCredentials {
        let parts = pasted.trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else { throw OAuthError.malformedCode }
        let pastedState = parts.count > 1 ? parts[1] : state
        return try await Self.exchange(code: code, state: pastedState,
                                       verifier: verifier, redirectURI: redirectURI)
    }

    func cancel() {
        server?.stop()
        server = nil
    }

    // MARK: - Construction

    private func authorizeURL() -> URL {
        var components = URLComponents(string: Self.authorizeBase)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: ClaudeAccountClient.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    private static func exchange(code: String, state: String,
                                 verifier: String, redirectURI: String) async throws -> OAuthCredentials {
        var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": ClaudeAccountClient.clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
        request.timeoutInterval = 20

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            throw OAuthError.exchangeFailed(0)
        }
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = root["access_token"] as? String, !accessToken.isEmpty else {
            DiagnosticLog.append("échange OAuth HTTP \(status)")
            throw OAuthError.exchangeFailed(status)
        }

        let refreshToken = root["refresh_token"] as? String
        let expiresIn = (root["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let expiresAt = Date().addingTimeInterval(expiresIn)

        // Même forme de document que Claude Code : un seul format à parser partout.
        var oauth: [String: Any] = [
            "accessToken": accessToken,
            "expiresAt": Int(expiresAt.timeIntervalSince1970 * 1000),
        ]
        if let refreshToken { oauth["refreshToken"] = refreshToken }
        if let scope = root["scope"] as? String { oauth["scopes"] = scope.split(separator: " ").map(String.init) }

        DiagnosticLog.append("connexion OAuth réussie")
        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            root: ["claudeAiOauth": oauth],
            source: .ownKeychain
        )
    }

    // MARK: - PKCE

    private static func randomURLSafe(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return Data(buffer).base64URLEncoded
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Serveur loopback

/// Mini serveur HTTP une-requête : reçoit `GET /callback?code=…&state=…`, répond une page
/// de confirmation, et rend le code. Les requêtes parasites (favicon…) sont ignorées.
private final class LoopbackServer: @unchecked Sendable {

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.claudy.oauth-loopback")
    private var finished = false

    /// Test de disponibilité synchrone : `NWListener` ne signale un port occupé
    /// qu'après coup, trop tard pour choisir le mode.
    static func portAvailable(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!
        )
        listener = try NWListener(using: parameters)
    }

    func stop() {
        queue.async { [self] in
            finished = true
            listener.cancel()
        }
    }

    func waitForCode(expectedState: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (Result<String, Error>) -> Void = { [self] result in
                queue.async { [self] in
                    guard !finished else { return }
                    finished = true
                    listener.cancel()
                    continuation.resume(with: result)
                }
            }

            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let code = Self.queryValue("code", in: request)
                    let state = Self.queryValue("state", in: request)

                    // Pas de code : requête parasite (favicon…) — on répond et on attend la vraie.
                    guard let code else {
                        Self.respond(connection, body: "", status: "404 Not Found")
                        return
                    }

                    let ok = state == expectedState
                    Self.respond(connection, body: ok ? Self.successPage : Self.failurePage)
                    finish(ok ? .success(code) : .failure(OAuthError.stateMismatch))
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { finish(.failure(error)) }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(OAuthError.timedOut))
            }
        }
    }

    private static func respond(_ connection: NWConnection, body: String, status: String = "200 OK") {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Extrait un paramètre de la première ligne `GET /callback?… HTTP/1.1`.
    private static func queryValue(_ name: String, in request: String) -> String? {
        guard let line = request.components(separatedBy: "\r\n").first,
              let pathPart = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(pathPart)) else { return nil }
        guard let value = components.queryItems?.first(where: { $0.name == name })?.value,
              !value.isEmpty else { return nil }
        return value
    }

    private static let successPage = """
    <html><head><meta charset="utf-8"><title>Claudy</title></head>
    <body style="font-family:-apple-system,sans-serif;background:#141210;color:#eee;\
    display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
    <div style="text-align:center"><div style="font-size:44px">✳︎</div>
    <h2>Claudy est connecté</h2><p style="color:#999">Tu peux fermer cet onglet.</p></div>
    </body></html>
    """

    private static let failurePage = """
    <html><head><meta charset="utf-8"><title>Claudy</title></head>
    <body style="font-family:-apple-system,sans-serif;background:#141210;color:#eee;\
    display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
    <div style="text-align:center"><h2>Réponse inattendue</h2>
    <p style="color:#999">Retourne dans Claudy et réessaie.</p></div>
    </body></html>
    """
}
