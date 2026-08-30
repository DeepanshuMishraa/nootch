import Foundation
import Security

struct ClaudeAdapter: ProviderAdapter {
    let provider: ProviderID = .claude

    func detect() async -> DetectionResult {
        DetectionResult(detected: Self.accessToken() != nil, source: "Claude OAuth")
    }

    func fetch() async -> ProviderStatus {
        guard let token = Self.accessToken() else { return .unavailable(.claude, detected: false) }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return .unavailable(.claude, detected: true, source: "Claude OAuth", error: "Invalid Claude usage endpoint.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
            guard http.statusCode == 200 else { throw ClaudeError.http(http.statusCode) }
            let usage = try JSONDecoder().decode(Response.self, from: data)
            return ProviderStatus(
                provider: .claude,
                detected: true,
                source: "Claude OAuth",
                primary: usage.fiveHour?.usageWindow(minutes: 300),
                secondary: usage.sevenDay?.usageWindow(minutes: 10080),
                error: nil,
                updatedAt: Date())
        } catch {
            return .unavailable(
                .claude,
                detected: true,
                source: "Claude OAuth",
                error: (error as? ClaudeError)?.description ?? "Could not read Claude usage: \(error.localizedDescription)")
        }
    }

    private struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        enum CodingKeys: String, CodingKey { case fiveHour = "five_hour", sevenDay = "seven_day" }
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }

        func usageWindow(minutes: Int) -> UsageWindow? {
            guard let utilization else { return nil }
            return UsageWindow(
                usedPercent: utilization,
                windowMinutes: minutes,
                resetsAt: resetsAt.flatMap(Self.parseDate))
        }

        private static func parseDate(_ value: String) -> Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
    }

    private enum ClaudeError: Error {
        case invalidResponse
        case http(Int)
        var description: String {
            switch self {
            case .invalidResponse: "Invalid Claude usage response."
            case let .http(code): code == 401 || code == 403
                ? "Claude login expired. Run `claude` to sign in again."
                : "Claude usage API returned HTTP \(code)."
            }
        }
    }

    private static func accessToken() -> String? {
        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
