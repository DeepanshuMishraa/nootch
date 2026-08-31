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
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 10) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
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
            let token = try await ProviderProcess.run("/usr/bin/sqlite3", arguments: [databasePath, "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"])
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
            let primary = summary.primaryWindow
            return ProviderStatus(provider: .cursor, detected: true, source: "Cursor app auth", primary: primary, secondary: nil, error: nil, updatedAt: Date())
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

    private static func githubToken() async -> String? {
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty { return token }
        return try? await ProviderProcess.run("/usr/bin/env", arguments: ["gh", "auth", "token"])
    }
}
