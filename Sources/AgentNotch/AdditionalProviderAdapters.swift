import Foundation

private enum AdditionalProviderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { value } else { nil } }
}

private enum AdditionalProviderHTTP {
    static func get(_ urlString: String, bearer: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw AdditionalProviderError.message("Invalid provider endpoint.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdditionalProviderError.message("Invalid provider response.") }
        return (data, http)
    }
}

private func statusError(_ provider: ProviderID, source: String, error: Error) -> ProviderStatus {
    .unavailable(provider, detected: true, source: source, error: error.localizedDescription)
}

struct OpenCodeGoAdapter: ProviderAdapter {
    let provider: ProviderID = .openCode
    private let authURL = NSString(string: "~/.local/share/opencode/auth.json").expandingTildeInPath

    func detect() async -> DetectionResult {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authURL)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object["opencode-go"] as? [String: Any],
              let key = entry["key"] as? String, !key.isEmpty
        else { return DetectionResult(detected: false, source: nil) }
        return DetectionResult(detected: true, source: "OpenCode Go credentials")
    }

    func fetch() async -> ProviderStatus {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authURL)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object["opencode-go"] as? [String: Any],
              let key = entry["key"] as? String, !key.isEmpty
        else { return .unavailable(.openCode, detected: false) }
        do {
            let (data, response) = try await AdditionalProviderHTTP.get("https://opencode.ai/zen/go/v1/usage", bearer: key)
            guard response.statusCode == 200 else {
                if response.statusCode == 403 {
                    return .unavailable(.openCode, detected: false, source: "OpenCode Go")
                }
                throw AdditionalProviderError.message("OpenCode Go returned HTTP \(response.statusCode).")
            }
            let windows = Self.windows(from: data)
            guard windows.0 != nil else { throw AdditionalProviderError.message("OpenCode Go returned no usage windows.") }
            return ProviderStatus(provider: .openCode, detected: true, source: "OpenCode Go API", primary: windows.0, secondary: windows.1, error: nil, updatedAt: Date())
        } catch { return statusError(.openCode, source: "OpenCode Go API", error: error) }
    }

    private static func windows(from data: Data) -> (UsageWindow?, UsageWindow?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return (nil, nil) }
        var candidates: [(String, UsageWindow)] = []
        collect(root, path: [], into: &candidates)
        let rolling = candidates.first { $0.0.contains("rolling") || $0.0.contains("session") || $0.0.contains("5h") }
        let weekly = candidates.first { $0.0.contains("week") }
        return (rolling?.1 ?? candidates.first?.1, weekly?.1)
    }

    private static func collect(_ value: Any, path: [String], into result: inout [(String, UsageWindow)]) {
        if let object = value as? [String: Any] {
            let percentKey = ["percentUsed", "usagePercent", "usedPercent", "percent", "utilization"].first { object[$0] != nil }
            if let percentKey, let percent = object[percentKey] as? Double {
                let reset = (object["resetAt"] as? String).flatMap(parseAdditionalDate)
                result.append((path.joined(separator: ".").lowercased(), UsageWindow(usedPercent: percent, resetsAt: reset)))
            } else if let used = object["used"] as? Double, let limit = object["limit"] as? Double, limit > 0 {
                result.append((path.joined(separator: ".").lowercased(), UsageWindow(usedPercent: used / limit * 100)))
            }
            for (key, child) in object { collect(child, path: path + [key], into: &result) }
        } else if let array = value as? [Any] {
            for child in array { collect(child, path: path, into: &result) }
        }
    }
}

struct OpenCodeAdapter: ProviderAdapter {
    let provider: ProviderID = .openCode

    static var isInstalled: Bool {
        let candidates = [
            "~/.local/bin/opencode",
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "/usr/bin/opencode",
        ].map { NSString(string: $0).expandingTildeInPath }
        let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            ?? (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .split(separator: ":")
                .map { "\($0)/opencode" }
                .first(where: FileManager.default.isExecutableFile(atPath:))
        return executable != nil || Self.credential(for: "opencode-go") != nil || Self.credential(for: "opencode") != nil
    }

    func detect() async -> DetectionResult {
        guard Self.isInstalled else { return DetectionResult(detected: false, source: nil) }
        return DetectionResult(detected: true, source: "OpenCode CLI")
    }

    func fetch() async -> ProviderStatus {
        guard (await detect()).detected else { return .unavailable(.openCode, detected: false) }

        if Self.credential(for: "opencode-go") != nil {
            let goStatus = await OpenCodeGoAdapter().fetch()
            if goStatus.detected { return goStatus }
        }

        if Self.credential(for: "opencode") != nil {
            return .unavailable(.openCode, detected: true, source: "OpenCode Zen")
        }

        return .unavailable(
            .openCode,
            detected: false,
            source: "OpenCode subscription",
            error: "OpenCode subscription is not active.")
    }

    private static func credential(for provider: String) -> String? {
        let path = NSString(string: "~/.local/share/opencode/auth.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object[provider] as? [String: Any],
              let key = entry["key"] as? String,
              !key.isEmpty else { return nil }
        return key
    }
}

struct ClinePassAdapter: ProviderAdapter {
    let provider: ProviderID = .clinePass

    func detect() async -> DetectionResult {
        guard Self.apiKey() != nil else { return DetectionResult(detected: false, source: nil) }
        return DetectionResult(detected: true, source: "ClinePass API key")
    }

    func fetch() async -> ProviderStatus {
        guard let key = Self.apiKey() else { return .unavailable(.clinePass, detected: false) }
        do {
            let (data, response) = try await AdditionalProviderHTTP.get("https://api.cline.bot/api/v1/users/me/plan/usage-limits", bearer: key)
            guard response.statusCode == 200 else { throw AdditionalProviderError.message(response.statusCode == 401 || response.statusCode == 403 ? "ClinePass API key was rejected." : "ClinePass returned HTTP \(response.statusCode).") }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["data"] as? [String: Any],
                  let limits = payload["limits"] as? [[String: Any]] else { throw AdditionalProviderError.message("ClinePass returned an invalid usage response.") }
            var fiveHour: UsageWindow?
            var weekly: UsageWindow?
            for limit in limits {
                guard let type = limit["type"] as? String, let used = limit["percentUsed"] as? Double else { continue }
                let window = UsageWindow(usedPercent: used, windowMinutes: type == "weekly" ? 10080 : 300, resetsAt: (limit["resetsAt"] as? String).flatMap(parseAdditionalDate))
                if type == "five_hour" { fiveHour = window }
                if type == "weekly" { weekly = window }
            }
            guard fiveHour != nil || weekly != nil else { throw AdditionalProviderError.message("ClinePass returned no supported usage limits.") }
            return ProviderStatus(provider: .clinePass, detected: true, source: "ClinePass API", primary: fiveHour ?? weekly, secondary: weekly, error: nil, updatedAt: Date())
        } catch { return statusError(.clinePass, source: "ClinePass API", error: error) }
    }

    private static func apiKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["CLINE_API_KEY", "CLINEPASS_API_KEY"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }
}

private func parseAdditionalDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
