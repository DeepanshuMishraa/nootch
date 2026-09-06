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
        request.setValue("nootch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FetchError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
            let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            return ProviderStatus(provider: .codex, detected: true, source: "Codex OAuth", primary: usage.rateLimit?.primaryWindow?.window, secondary: usage.rateLimit?.secondaryWindow?.window, error: nil, updatedAt: Date(), costUsage: TokenUsageScanner.scanCodex())
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
            guard http.statusCode == 200 else {
                // The cached token is no longer good; drop it so the next cycle
                // re-reads instead of waiting out the TTL on a stale value.
                // Only worth doing when the cache is what supplied the token;
                // an env-var token is never cached, so clearing would be a
                // no-op that just hides the real problem.
                if http.statusCode == 401 || http.statusCode == 403, Self.environmentToken() == nil {
                    Self.tokenCache.invalidate()
                }
                throw ClaudeError.http(http.statusCode)
            }
            let usage = try JSONDecoder().decode(Response.self, from: data)
            return ProviderStatus(
                provider: .claude,
                detected: true,
                source: "Claude OAuth",
                primary: usage.fiveHour?.usageWindow(minutes: 300),
                secondary: usage.sevenDay?.usageWindow(minutes: 10080),
                error: nil,
                updatedAt: Date(),
                costUsage: TokenUsageScanner.scanClaude())
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

    private enum TokenLookup {
        case found(String)
        // Nothing stored anywhere. Re-reading is cheap and raises no prompt, so
        // this expires quickly and a fresh `claude login` shows up promptly.
        case absent
        // The Keychain refused: the prompt was cancelled, or authentication
        // failed. Re-reading means another password dialog, so back off hard.
        case denied
    }

    // A Keychain read of "Claude Code-credentials" can raise a system password
    // prompt, and the refresh loop runs every 30s. Caching the result keeps a
    // signed build to one prompt per TTL, and keeps an unsigned or denied one
    // from producing a dialog every half minute.
    private final class TokenCache: @unchecked Sendable {
        private static let foundTTL: TimeInterval = 300
        private static let absentTTL: TimeInterval = 30
        private static let deniedTTL: TimeInterval = 600
        // Floor between a rejected token and the next read, so a token the API
        // keeps refusing cannot turn into a prompt every cycle.
        private static let reloadFloor: TimeInterval = 120

        private let lock = NSLock()
        private var token: String?
        private var expiresAt: Date?
        private var earliestReload: Date?

        // `loader` runs while the lock is held, so it must not call back into
        // the cache. It is only ever the Keychain/file read below.
        func value(loader: () -> TokenLookup) -> String? {
            lock.lock()
            defer { lock.unlock() }
            let now = Date()
            if let expiresAt, now < expiresAt { return token }
            // Expired, but still inside the post-rejection floor: keep serving
            // the stale token so the "login expired" error stays put instead of
            // the row flipping to undetected, and do not touch the Keychain.
            if let earliestReload, now < earliestReload { return token }

            let ttl: TimeInterval
            switch loader() {
            case let .found(value):
                token = value
                ttl = Self.foundTTL
            case .absent:
                token = nil
                ttl = Self.absentTTL
            case .denied:
                token = nil
                ttl = Self.deniedTTL
            }
            expiresAt = now.addingTimeInterval(ttl)
            earliestReload = nil
            return token
        }

        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            expiresAt = nil
            earliestReload = Date().addingTimeInterval(Self.reloadFloor)
        }
    }

    private static let tokenCache = TokenCache()

    private static func environmentToken() -> String? {
        guard let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty
        else { return nil }
        return token
    }

    private static func accessToken() -> String? {
        if let token = environmentToken() { return token }
        return tokenCache.value(loader: lookupToken)
    }

    private static func lookupToken() -> TokenLookup {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let token = oauthAccessToken(from: data) {
            return .found(token)
        }
        if let token = credentialsFileToken() { return .found(token) }
        // errSecItemNotFound means there is simply nothing stored; anything else
        // is the Keychain declining to hand it over.
        return status == errSecItemNotFound ? .absent : .denied
    }

    // Claude Code also writes ~/.claude/.credentials.json on some setups. It is
    // only a fallback: the Keychain stays authoritative so a refreshed token is
    // never shadowed by a stale file.
    private static func credentialsFileToken() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return oauthAccessToken(from: data)
    }

    private static func oauthAccessToken(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
import Foundation

private enum ProviderFetchFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { message } else { nil } }
}

private func failedStatus(provider: ProviderID, source: String, error: Error) -> ProviderStatus {
    .unavailable(provider, detected: true, source: source, error: error.localizedDescription)
}

private actor AgyProcessKeeper {
    static let shared = AgyProcessKeeper()
    private var process: Process?
    private var input: Pipe?

    func ensureRunning(executable: String) throws {
        if let process, process.isRunning { return }
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", executable, "--dangerously-skip-permissions"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        self.input = input
    }
}

private enum ProviderProcess {
    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 10,
        environment: [String: String]? = nil) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
            }
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline { usleep(50_000) }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw ProviderFetchFailure.message(message.isEmpty ? "Provider command failed." : message)
            }
            return String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    static func launchAgy() async throws {
        let candidates = [
            "~/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
            "/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos",
            "~/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
            "~/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos",
        ].map { NSString(string: $0).expandingTildeInPath }
        if let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            try await AgyProcessKeeper.shared.ensureRunning(executable: executable)
            return
        }
        let executable = try await run("/usr/bin/which", arguments: ["agy"])
        try await AgyProcessKeeper.shared.ensureRunning(executable: executable)
    }
}

private func parseISODate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

struct AntigravityAdapter: ProviderAdapter {
    let provider: ProviderID = .antigravity

    func detect() async -> DetectionResult {
        let appSupport = NSString(string: "~/Library/Application Support/Antigravity").expandingTildeInPath
        let candidates = ["~/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
            .map { NSString(string: $0).expandingTildeInPath }
        let installed = FileManager.default.fileExists(atPath: appSupport)
            || candidates.contains(where: FileManager.default.isExecutableFile(atPath:))
        return DetectionResult(detected: installed, source: "Antigravity local quota")
    }

    func fetch() async -> ProviderStatus {
        await fetch(attemptLaunch: true)
    }

    private func fetch(attemptLaunch: Bool) async -> ProviderStatus {
        guard (await detect()).detected else { return .unavailable(.antigravity, detected: false) }
        do {
            let processes = try await ProviderProcess.run("/usr/bin/pgrep", arguments: ["-x", "agy"])
            let pids = processes.split(separator: "\n").map(String.init)
            var lastError: Error = ProviderFetchFailure.message("Antigravity quota service did not answer. Retrying automatically.")
            for pid in pids {
                do {
                    let listeners = try await ProviderProcess.run("/usr/sbin/lsof", arguments: ["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN"])
                    let regex = try NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#)
                    let range = NSRange(listeners.startIndex..., in: listeners)
                    let ports = regex.matches(in: listeners, range: range).compactMap { match -> String? in
                        Range(match.range(at: 1), in: listeners).map { String(listeners[$0]) }
                    }
                    for port in ports {
                        do {
                            let output = try await ProviderProcess.run("/usr/bin/curl", arguments: [
                                "-ksS", "--max-time", "5", "-H", "Content-Type: application/json", "-d", "{}",
                                "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
                            ])
                            guard let data = output.data(using: .utf8) else { continue }
                            let windows = try Self.parseSummary(data)
                            return ProviderStatus(provider: .antigravity, detected: true, source: "agy local quota", primary: windows.0, secondary: windows.1, error: nil, updatedAt: Date())
                        } catch { lastError = error }
                    }
                } catch { lastError = error }
            }
            if attemptLaunch {
                try await ProviderProcess.launchAgy()
                try await Task.sleep(for: .seconds(8))
                return await fetch(attemptLaunch: false)
            }
            throw lastError
        } catch {
            if attemptLaunch {
                do {
                    try await ProviderProcess.launchAgy()
                    try await Task.sleep(for: .seconds(8))
                    return await fetch(attemptLaunch: false)
                } catch {
                    return failedStatus(provider: .antigravity, source: "Antigravity local quota", error: error)
                }
            }
            return failedStatus(provider: .antigravity, source: "Antigravity local quota", error: error)
        }
    }

    private static func parseSummary(_ data: Data) throws -> (UsageWindow?, UsageWindow?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["response"] as? [String: Any],
              let groups = response["groups"] as? [[String: Any]] else {
            throw ProviderFetchFailure.message("Antigravity returned an invalid quota response.")
        }
        let windows = groups.flatMap { group -> [(label: String, window: UsageWindow)] in
            guard let buckets = group["buckets"] as? [[String: Any]] else { return [] }
            return buckets.compactMap { bucket in
                let remaining: Double? = if let value = bucket["remainingFraction"] as? NSNumber {
                    value.doubleValue
                } else if let value = bucket["remainingFraction"] as? String {
                    Double(value)
                } else if let remainingObject = bucket["remaining"] as? [String: Any] {
                    (remainingObject["remainingFraction"] as? NSNumber)?.doubleValue
                        ?? (remainingObject["value"] as? NSNumber)?.doubleValue
                } else {
                    nil
                }
                guard let remaining else { return nil }
                let label = ((bucket["displayName"] as? String) ?? (bucket["window"] as? String) ?? "").lowercased()
                let minutes = label.contains("week") ? 10080 : label.contains("five") || label.contains("5 hour") ? 300 : nil
                let window = UsageWindow.fromRemainingPercent(
                    remaining * 100,
                    windowMinutes: minutes,
                    resetsAt: (bucket["resetTime"] as? String).flatMap(parseISODate))
                return (label: label, window: window)
            }
        }
        let fiveHour = windows.first { $0.label.contains("five") || $0.label.contains("5 hour") || $0.label.contains("5h") }?.window
        let weekly = windows.first { $0.label.contains("week") }?.window
        guard fiveHour != nil || weekly != nil else {
            throw ProviderFetchFailure.message("Antigravity returned no named quota windows.")
        }
        return (fiveHour ?? weekly, weekly)
    }
}

struct CursorAdapter: ProviderAdapter {
    let provider: ProviderID = .cursor
    private var databasePath: String { NSString(string: "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb").expandingTildeInPath }

    func detect() async -> DetectionResult {
        DetectionResult(detected: FileManager.default.fileExists(atPath: databasePath), source: "Cursor app auth")
    }

    func fetch() async -> ProviderStatus {
        guard (await detect()).detected else { return .unavailable(.cursor, detected: false) }
        do {
            let token = try await Self.readToken(from: databasePath)
            guard !token.isEmpty, let userID = Self.jwtSubject(token) else { throw ProviderFetchFailure.message("Cursor is not signed in.") }
            let cookie = "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
            guard let url = URL(string: "https://cursor.com/api/usage-summary") else { throw ProviderFetchFailure.message("Invalid Cursor usage endpoint.") }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ProviderFetchFailure.message("Cursor usage authentication failed.") }
            let summary = try JSONDecoder().decode(CursorSummary.self, from: data)
            if let primary = summary.primaryWindow {
                return ProviderStatus(provider: .cursor, detected: true, source: "Cursor app auth", primary: primary, secondary: nil, error: nil, updatedAt: Date())
            }
            throw ProviderFetchFailure.message("Cursor returned no usage window.")
        } catch {
            return await fetchLegacy(databasePath: databasePath, originalError: error)
        }
    }

    private func fetchLegacy(databasePath: String, originalError: Error) async -> ProviderStatus {
        do {
            let token = try await Self.readToken(from: databasePath)
            guard let userID = Self.jwtSubject(token), var components = URLComponents(string: "https://cursor.com/api/usage") else { throw originalError }
            components.queryItems = [URLQueryItem(name: "user", value: userID)]
            guard let url = components.url else { throw originalError }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw originalError }
            let summary = try JSONDecoder().decode(CursorSummary.self, from: data)
            return ProviderStatus(provider: .cursor, detected: true, source: "Cursor app auth", primary: summary.primaryWindow, secondary: nil, error: nil, updatedAt: Date())
        } catch { return failedStatus(provider: .cursor, source: "Cursor app auth", error: error) }
    }

    private struct CursorSummary: Decodable {
        struct Usage: Decodable { let plan: Plan?, overall: Plan? }
        struct Plan: Decodable { let used: Int?, limit: Int?, totalPercentUsed: Double? }
        let billingCycleEnd: String?
        let individualUsage: Usage?
        var primaryWindow: UsageWindow? {
            let plan = individualUsage?.plan ?? individualUsage?.overall
            let used = plan?.totalPercentUsed ?? {
                guard let used = plan?.used, let limit = plan?.limit, limit > 0 else { return nil }
                return Double(used) / Double(limit) * 100
            }()
            return used.map { UsageWindow(usedPercent: $0, resetsAt: billingCycleEnd.flatMap(parseISODate)) }
        }
    }

    private static func readToken(from databasePath: String) async throws -> String {
        let hex = try await ProviderProcess.run("/usr/bin/sqlite3", arguments: ["-readonly", databasePath, "SELECT hex(value) FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"])
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard next > index, let byte = UInt8(hex[index..<next], radix: 16) else { break }
            bytes.append(byte)
            index = next
        }
        let decoded = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? hex : decoded
    }

    private static func jwtSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["sub"] as? String
    }
}

struct CopilotAdapter: ProviderAdapter {
    let provider: ProviderID = .copilot

    func detect() async -> DetectionResult {
        DetectionResult(detected: await Self.githubToken() != nil, source: "GitHub OAuth")
    }

    func fetch() async -> ProviderStatus {
        guard let token = await Self.githubToken() else { return .unavailable(.copilot, detected: false) }
        do {
            guard let url = URL(string: "https://api.github.com/copilot_internal/user") else { throw ProviderFetchFailure.message("Invalid Copilot usage endpoint.") }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
            request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ProviderFetchFailure.message("Copilot usage authentication failed.") }
            let usage = try JSONDecoder().decode(CopilotResponse.self, from: data)
            let reset = usage.quotaResetDate.flatMap(parseISODate)
            return ProviderStatus(
                provider: .copilot,
                detected: true,
                source: "GitHub Copilot API",
                primary: usage.quotaSnapshots.premiumInteractions?.window(reset: reset),
                secondary: usage.quotaSnapshots.chat?.window(reset: reset),
                error: nil,
                updatedAt: Date())
        } catch { return failedStatus(provider: .copilot, source: "GitHub Copilot API", error: error) }
    }

    private struct CopilotResponse: Decodable {
        struct Snapshots: Decodable {
            let premiumInteractions: Quota?
            let chat: Quota?
            enum CodingKeys: String, CodingKey { case premiumInteractions = "premium_interactions", chat }
        }
        struct Quota: Decodable {
            let percentRemaining: Double?
            let unlimited: Bool?
            enum CodingKeys: String, CodingKey { case percentRemaining = "percent_remaining", unlimited }
            func window(reset: Date?) -> UsageWindow? {
                guard unlimited != true, let percentRemaining else { return nil }
                return UsageWindow.fromRemainingPercent(percentRemaining, resetsAt: reset)
            }
        }
        let quotaSnapshots: Snapshots
        let quotaResetDate: String?
        enum CodingKeys: String, CodingKey { case quotaSnapshots = "quota_snapshots", quotaResetDate = "quota_reset_date" }
    }

    private struct CopilotApp: Decodable {
        let oauthToken: String?

        enum CodingKeys: String, CodingKey {
            case oauthToken = "oauth_token"
        }
    }

    private static func githubToken() async -> String? {
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }

        // Finder-launched apps do not inherit the shell's PATH, so check the
        // standard gh locations explicitly before using Copilot's fallback token.
        let candidates = [
            "~/.local/bin/gh",
            "~/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ].map { NSString(string: $0).expandingTildeInPath }
        let ghEnvironment = [
            "HOME": NSHomeDirectory(),
            "GH_CONFIG_DIR": NSString(string: "~/.config/gh").expandingTildeInPath,
        ]
        if let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)),
           let token = try? await ProviderProcess.run(executable, arguments: ["auth", "token"], environment: ghEnvironment),
           !token.isEmpty {
            return token
        }

        // Keep support for custom shell installations as a final fallback.
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/gh" }
        if let executable = pathCandidates.first(where: FileManager.default.isExecutableFile(atPath:)),
           let token = try? await ProviderProcess.run(executable, arguments: ["auth", "token"], environment: ghEnvironment),
           !token.isEmpty {
            return token
        }

        // The Copilot CLI stores its OAuth token here. This covers machines
        // with Copilot installed but without a separately authenticated gh CLI.
        let appsPath = NSString(string: "~/.config/github-copilot/apps.json").expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: appsPath)),
           let apps = try? JSONDecoder().decode([String: CopilotApp].self, from: data),
           let token = apps.values.compactMap(\.oauthToken).first(where: { !$0.isEmpty }) {
            return token
        }
        return nil
    }
}
import Foundation
import Security

private enum AdditionalProviderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { value } else { nil } }
}

private enum AdditionalProviderHTTP {
    static func get(_ urlString: String, bearer: String? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw AdditionalProviderError.message("Invalid provider endpoint.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdditionalProviderError.message("Invalid provider response.") }
        return (data, http)
    }
}

private func statusError(_ provider: ProviderID, source: String, error: Error) -> ProviderStatus {
    let message: String
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            message = "Cannot reach \(source). Check your network connection."
        case .timedOut:
            message = "\(source) timed out. Try refreshing again."
        default:
            message = "Could not read \(source): \(urlError.localizedDescription)"
        }
    } else {
        message = error.localizedDescription
    }
    return .unavailable(provider, detected: true, source: source, error: message)
}

private func httpError(_ provider: String, status: Int) -> AdditionalProviderError {
    switch status {
    case 401, 403: return .message("\(provider) rejected the saved credentials. Sign in again or replace the API key.")
    case 404: return .message("\(provider) usage endpoint was not found. The provider may have changed its API.")
    case 429: return .message("\(provider) rate-limited the usage request. Try refreshing again shortly.")
    default: return .message("\(provider) returned HTTP \(status).")
    }
}

private enum ProviderSecret {
    static func value(environmentNames: [String], keychainAccount: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let value = environmentNames.lazy.compactMap({ environment[$0] }).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
            return value
        }
        // Existing credentials remain readable without rewriting Keychain items.
        for service in ["nootch", "AgentNotch"] {
            if let value = keychainValue(service: service, account: keychainAccount) {
                return value
            }
        }
        return nil
    }

    private static func keychainValue(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

private func jsonNumber(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) }
    return nil
}

private func firstJSONNumber(_ value: Any, keys: Set<String>) -> Double? {
    if let object = value as? [String: Any] {
        for (key, child) in object {
            if keys.contains(key), let number = jsonNumber(child) { return number }
            if let number = firstJSONNumber(child, keys: keys) { return number }
        }
    } else if let array = value as? [Any] {
        for child in array {
            if let number = firstJSONNumber(child, keys: keys) { return number }
        }
    }
    return nil
}

private func parseProviderDate(_ value: Any?) -> Date? {
    guard let string = value as? String else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}

struct OpenCodeAdapter: ProviderAdapter {
    let provider: ProviderID = .openCode

    static var isInstalled: Bool {
        credential(for: "opencode-go") != nil || credential(for: "opencode") != nil || apiKey() != nil || commandExists("opencode")
    }

    func detect() async -> DetectionResult {
        guard Self.isInstalled else { return DetectionResult(detected: false, source: nil) }
        return DetectionResult(detected: true, source: "OpenCode CLI or credentials")
    }

    func fetch() async -> ProviderStatus {
        guard let key = Self.credential(for: "opencode-go") ?? Self.credential(for: "opencode") ?? Self.apiKey() else {
            return .unavailable(.openCode, detected: false)
        }
        do {
            let (data, response) = try await AdditionalProviderHTTP.get("https://opencode.ai/zen/go/v1/usage", bearer: key)
            guard response.statusCode == 200 else { throw httpError("OpenCode", status: response.statusCode) }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdditionalProviderError.message("OpenCode returned invalid JSON.") }
            let container = (root["usage"] as? [String: Any]) ?? (root["data"] as? [String: Any]) ?? root
            let windows = [
                ("rolling", ["rollingUsage", "rolling", "rolling_usage", "rollingWindow"]),
                ("weekly", ["weeklyUsage", "weekly", "weekly_usage", "weeklyWindow"]),
                ("monthly", ["monthlyUsage", "monthly", "monthly_usage", "monthlyWindow"]),
            ].compactMap { id, keys -> UsageWindow? in
                guard let lane = keys.lazy.compactMap({ container[$0] as? [String: Any] }).first,
                      let percent = firstJSONNumber(lane, keys: ["usagePercent", "usage_percent", "percentUsed", "used_percent", "percent"]) else { return nil }
                let reset = firstJSONNumber(lane, keys: ["resetInSec", "resetInSeconds", "reset_in_sec"]).map { Date().addingTimeInterval($0) }
                return UsageWindow(usedPercent: percent, windowMinutes: id == "weekly" ? 10080 : nil, resetsAt: reset)
            }
            guard let primary = windows.first else { throw AdditionalProviderError.message("OpenCode returned no usage windows.") }
            return ProviderStatus(provider: .openCode, detected: true, source: "OpenCode usage API", primary: primary, secondary: windows.dropFirst().first, error: nil, updatedAt: Date())
        } catch { return statusError(.openCode, source: "OpenCode usage API", error: error) }
    }

    fileprivate static func apiKey() -> String? {
        ProviderSecret.value(environmentNames: ["OPENCODE_API_KEY", "OPENCODE_GO_API_KEY"], keychainAccount: "opencode.apiKey")
    }

    fileprivate static func credential(for provider: String) -> String? {
        let path = NSString(string: "~/.local/share/opencode/auth.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object[provider] as? [String: Any],
              let key = (entry["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    private static func commandExists(_ command: String) -> Bool {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(command)") }
    }
}

struct ZaiAdapter: ProviderAdapter {
    let provider: ProviderID = .zai

    func detect() async -> DetectionResult { DetectionResult(detected: Self.apiKey() != nil, source: "Z.ai API key") }

    func fetch() async -> ProviderStatus {
        guard let key = Self.apiKey() else { return .unavailable(.zai, detected: false) }
        let china = ProcessInfo.processInfo.environment["ZAI_REGION"]?.lowercased() == "china"
        let host = china ? "https://open.bigmodel.cn" : "https://api.z.ai"
        do {
            let (data, response) = try await AdditionalProviderHTTP.get(host + "/api/monitor/usage/quota/limit", bearer: key)
            guard response.statusCode == 200 else { throw httpError("Z.ai", status: response.statusCode) }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObject = root["data"] as? [String: Any] ?? Optional(root),
                  let limits = dataObject["limits"] as? [[String: Any]] else { throw AdditionalProviderError.message("Z.ai returned invalid quota data.") }
            let parsed = limits.compactMap { item -> (Double, UsageWindow)? in
                guard let type = item["type"] as? String else { return nil }
                let cap = jsonNumber(item["usage"])
                let current = jsonNumber(item["currentValue"])
                let remaining = jsonNumber(item["remaining"])
                let used = current ?? cap.map { max(0, $0 - (remaining ?? $0)) }
                let percent = jsonNumber(item["percentage"])
                guard (cap != nil && used != nil) || percent != nil else { return nil }
                let unit = jsonNumber(item["unit"]).map(Int.init)
                let count = jsonNumber(item["number"]).map(Int.init)
                let minutes = unit.flatMap { unit -> Int? in
                    guard let count, count > 0 else { return nil }
                    return [1: 1440, 3: 60, 5: 1, 6: 10080][unit].map { count * $0 }
                }
                let window = cap.flatMap { limit in used.map { UsageWindow(usedPercent: limit > 0 ? $0 / limit * 100 : 0, windowMinutes: minutes, resetsAt: parseProviderDate(item["nextResetTime"])) } }
                    ?? UsageWindow(usedPercent: percent ?? 0, windowMinutes: minutes, resetsAt: parseProviderDate(item["nextResetTime"]))
                return (type == "TIME_LIMIT" ? .greatestFiniteMagnitude : Double(minutes ?? Int.max), window)
            }.sorted { $0.0 < $1.0 }.map { $0.1 }
            guard let primary = parsed.first else { throw AdditionalProviderError.message("Z.ai returned no supported quota windows.") }
            return ProviderStatus(provider: .zai, detected: true, source: "Z.ai usage API", primary: primary, secondary: parsed.dropFirst().first, error: nil, updatedAt: Date())
        } catch { return statusError(.zai, source: "Z.ai usage API", error: error) }
    }

    private static func apiKey() -> String? {
        ProviderSecret.value(environmentNames: ["ZAI_API_KEY", "ZHIPUAI_API_KEY", "BIGMODEL_API_KEY"], keychainAccount: "zai.apiKey")
    }
}

struct GrokAdapter: ProviderAdapter {
    let provider: ProviderID = .grok

    func detect() async -> DetectionResult { DetectionResult(detected: Self.token() != nil, source: "Grok CLI credentials") }

    func fetch() async -> ProviderStatus {
        guard let token = Self.token() else { return .unavailable(.grok, detected: false) }
        do {
            async let monthly = AdditionalProviderHTTP.get("https://cli-chat-proxy.grok.com/v1/billing", bearer: token, headers: ["x-xai-token-auth": "xai-grok-cli"])
            async let credits = AdditionalProviderHTTP.get("https://cli-chat-proxy.grok.com/v1/billing?format=credits", bearer: token, headers: ["x-xai-token-auth": "xai-grok-cli"])
            let results = try await (monthly, credits)
            let windows = Self.windows(monthly: results.0.0, credits: results.1.0)
            guard let primary = windows.first else { throw AdditionalProviderError.message("Grok returned no usage windows.") }
            return ProviderStatus(provider: .grok, detected: true, source: "Grok billing API", primary: primary, secondary: windows.dropFirst().first, error: nil, updatedAt: Date())
        } catch { return statusError(.grok, source: "Grok billing API", error: error) }
    }

    private static func token() -> String? {
        if let value = ProviderSecret.value(environmentNames: ["GROK_API_KEY", "XAI_GROK_TOKEN"], keychainAccount: "grok.apiKey") { return value }
        let path = NSString(string: "~/.grok/auth.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let root = try? JSONSerialization.jsonObject(with: data), let object = root as? [String: Any] else { return nil }
        if let direct = ["access_token", "token", "key"].compactMap({ object[$0] as? String }).first(where: { !$0.isEmpty }) { return direct }
        return object.values.compactMap { ($0 as? [String: Any])?["key"] as? String ?? ($0 as? [String: Any])?["access_token"] as? String }.first(where: { !$0.isEmpty })
    }

    private static func windows(monthly: Data, credits: Data) -> [UsageWindow] {
        [credits, monthly].compactMap { data -> UsageWindow? in
            guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
            let config = (root as? [String: Any])?["config"] ?? root
            guard let percent = firstJSONNumber(config, keys: ["creditUsagePercent", "usage_percentage", "usagePercent"]) else { return nil }
            return UsageWindow(usedPercent: percent, resetsAt: parseProviderDate((config as? [String: Any])?["billingPeriodEnd"]))
        }
    }
}

struct XAIAdapter: ProviderAdapter {
    let provider: ProviderID = .xai

    func detect() async -> DetectionResult { DetectionResult(detected: Self.credentials != nil, source: "xAI management credentials") }

    func fetch() async -> ProviderStatus {
        guard let credentials = Self.credentials, let url = URL(string: "https://management-api.x.ai/v1/billing/teams/\(credentials.team)/prepaid/balance") else { return .unavailable(.xai, detected: false) }
        do {
            let (data, response) = try await AdditionalProviderHTTP.get(url.absoluteString, bearer: credentials.key)
            guard response.statusCode == 200 else { throw httpError("xAI", status: response.statusCode) }
            let root = try JSONSerialization.jsonObject(with: data)
            guard let cents = firstJSONNumber(root, keys: ["val", "total"]) else { throw AdditionalProviderError.message("xAI returned no prepaid balance.") }
            let remaining = max(0, -cents / 100)
            let budget = Double(ProcessInfo.processInfo.environment["XAI_MONTHLY_BUDGET"] ?? "") ?? max(remaining, 0.01)
            let used = budget > remaining ? (budget - remaining) / budget * 100 : 0
            return ProviderStatus(provider: .xai, detected: true, source: "xAI billing API", primary: UsageWindow(usedPercent: used), secondary: nil, error: nil, updatedAt: Date())
        } catch { return statusError(.xai, source: "xAI billing API", error: error) }
    }

    private static var credentials: (key: String, team: String)? {
        guard let key = ProviderSecret.value(environmentNames: ["XAI_MANAGEMENT_KEY", "XAI_API_KEY"], keychainAccount: "xai.managementKey") else { return nil }
        let team = (ProcessInfo.processInfo.environment["XAI_TEAM_ID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !team.isEmpty, team.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return (key, team)
    }
}

struct ClinePassAdapter: ProviderAdapter {
    let provider: ProviderID = .clinePass

    func detect() async -> DetectionResult { DetectionResult(detected: Self.apiKey() != nil, source: "ClinePass API key") }

    func fetch() async -> ProviderStatus {
        guard let key = Self.apiKey() else { return .unavailable(.clinePass, detected: false) }
        do {
            let (data, response) = try await AdditionalProviderHTTP.get("https://api.cline.bot/api/v1/users/me/plan/usage-limits", bearer: key)
            guard response.statusCode == 200 else { throw httpError("ClinePass", status: response.statusCode) }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = root["data"] as? [String: Any], let limits = payload["limits"] as? [[String: Any]] else { throw AdditionalProviderError.message("ClinePass returned invalid usage data.") }
            let windows = limits.compactMap { limit -> UsageWindow? in
                guard let type = limit["type"] as? String, let used = jsonNumber(limit["percentUsed"]) else { return nil }
                return UsageWindow(usedPercent: used, windowMinutes: type == "weekly" ? 10080 : 300, resetsAt: parseProviderDate(limit["resetsAt"]))
            }
            guard let primary = windows.first else { throw AdditionalProviderError.message("ClinePass returned no supported usage limits.") }
            return ProviderStatus(provider: .clinePass, detected: true, source: "ClinePass API", primary: primary, secondary: windows.dropFirst().first, error: nil, updatedAt: Date())
        } catch { return statusError(.clinePass, source: "ClinePass API", error: error) }
    }

    private static func apiKey() -> String? { ProviderSecret.value(environmentNames: ["CLINE_API_KEY", "CLINEPASS_API_KEY"], keychainAccount: "clinepass.apiKey") }
}
