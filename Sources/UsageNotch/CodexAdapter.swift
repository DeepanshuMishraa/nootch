import Foundation

struct CodexAdapter: ProviderAdapter {
    let provider: ProviderID = .codex

    func detect() async -> DetectionResult {
        guard let credentials = readCredentials() else {
            return DetectionResult(detected: Self.commandExists("codex"), source: "codex CLI")
        }
        return DetectionResult(detected: true, source: credentials.accountID == nil ? "Codex OAuth" : "Codex OAuth account")
    }

    func fetch() async -> ProviderStatus {
        guard let credentials = readCredentials() else {
            let detected = await detect()
            return .unavailable(.codex, detected: detected.detected, source: detected.source, error: detected.detected ? "Run `codex login` to enable usage." : nil)
        }
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return .unavailable(.codex, detected: true, source: "Codex OAuth", error: "Invalid Codex usage endpoint.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("UsageNotch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FetchError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
            let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            return ProviderStatus(provider: .codex, detected: true, source: "Codex OAuth", primary: usage.rateLimit?.primaryWindow?.window, secondary: usage.rateLimit?.secondaryWindow?.window, error: nil, updatedAt: Date())
        } catch is CancellationError {
            return .unavailable(.codex, detected: true, source: "Codex OAuth", error: "Refresh cancelled")
        } catch let error as FetchError {
            return .unavailable(.codex, detected: true, source: "Codex OAuth", error: error.description)
        } catch {
            return .unavailable(.codex, detected: true, source: "Codex OAuth", error: "Could not read Codex usage: \(error.localizedDescription)")
        }
    }

    private struct Credentials: Sendable {
        let accessToken: String
        let accountID: String?
    }

    private struct AuthFile: Decodable {
        let tokens: Tokens?
        let personalAccessToken: String?
        enum CodingKeys: String, CodingKey { case tokens, personalAccessToken = "personal_access_token" }
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", accountID = "account_id" }
    }

    private struct CodexUsageResponse: Decodable {
        let rateLimit: RateLimit?
        enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit" }
    }

    private struct RateLimit: Decodable { let primaryWindow: Window?, secondaryWindow: Window?
        enum CodingKeys: String, CodingKey { case primaryWindow = "primary_window", secondaryWindow = "secondary_window" }
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let resetAt: TimeInterval?
        let limitWindowSeconds: Int?
        var window: UsageWindow { UsageWindow(usedPercent: usedPercent, windowMinutes: limitWindowSeconds.map { $0 / 60 }, resetsAt: resetAt.map(Date.init(timeIntervalSince1970:))) }
        enum CodingKeys: String, CodingKey { case usedPercent = "used_percent", resetAt = "reset_at", limitWindowSeconds = "limit_window_seconds" }
    }

    private enum FetchError: Error {
        case invalidResponse
        case http(Int)
        var description: String { switch self { case .invalidResponse: "Invalid Codex usage response."; case let .http(code): code == 401 || code == 403 ? "Codex login expired. Run `codex login`." : "Codex usage API returned HTTP \(code)." } }
    }

    private func readCredentials() -> Credentials? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "~/.codex"
        let path = URL(fileURLWithPath: NSString(string: home).expandingTildeInPath).appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: path), let auth = try? JSONDecoder().decode(AuthFile.self, from: data) else { return nil }
        if let token = auth.tokens?.accessToken, !token.isEmpty { return Credentials(accessToken: token, accountID: auth.tokens?.accountID) }
        if let token = auth.personalAccessToken, !token.isEmpty { return Credentials(accessToken: token, accountID: nil) }
        return nil
    }

    private static func commandExists(_ command: String) -> Bool {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return paths.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(command)") }
    }
}
