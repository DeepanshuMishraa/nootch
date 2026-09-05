import Foundation

struct AgentActivitySnapshot: Sendable, Equatable {
    let activityByProvider: [ProviderID: AgentActivity]
    let isReliable: Bool
}

struct AgentActivityDetector: Sendable {
    private let processRunner: @Sendable () -> String

    init(processRunner: @escaping @Sendable () -> String = Self.readProcesses) {
        self.processRunner = processRunner
    }

    func snapshot(now: Date = Date()) -> AgentActivitySnapshot {
        let processes = processRunner()
        var activities: [ProviderID: AgentActivity] = [:]
        for process in processes.split(whereSeparator: \.isNewline) {
            let fields = process.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard fields.count == 5,
                  let cpu = Double(fields[2]),
                  let provider = Self.provider(for: String(fields[1]), arguments: String(fields[4]))
            else { continue }

            let activity = Self.classify(
                cpu: cpu,
                processState: String(fields[3]),
                approvalEvidence: false)
            activities[provider] = Self.moreUrgent(activities[provider], activity)
        }
        return AgentActivitySnapshot(activityByProvider: activities, isReliable: !processes.isEmpty)
    }

    private static func readProcesses() -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,%cpu=,state=,args="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    static func provider(for processName: String, arguments: String = "") -> ProviderID? {
        let name = URL(fileURLWithPath: processName).lastPathComponent.lowercased()
        let command = "\(name) \(arguments.lowercased())"
        if command.contains("cursor.app") || ["cursor", "cursor-agent"].contains(name) { return .cursor }
        if command.contains("claude.app") || ["claude", "claude-code"].contains(name) { return .claude }
        if command.contains("codex.app") || ["codex", "pi"].contains(name) { return .codex }
        if ["opencode", "open-code"].contains(name) { return .openCode }
        if ["grok", "grok-cli"].contains(name) { return .grok }
        if ["zai", "zhipu"].contains(name) { return .zai }
        if ["copilot", "github-copilot", "ghcs"].contains(name) { return .copilot }
        if ["agy", "antigravity"].contains(name) { return .antigravity }
        if name == "cline" { return .clinePass }
        return nil
    }

    static func classify(cpu: Double, processState: String = "", recentActivity: Bool = false, approvalEvidence: Bool) -> AgentActivity {
        if approvalEvidence { return .needsAction }
        let isExecuting = processState.contains("R") || processState.contains("U")
        return cpu >= 1.0 || isExecuting || recentActivity ? .working : .idle
    }

    private static func sessionRoots(for provider: ProviderID) -> [String] {
        switch provider {
        case .claude: ["~/.claude/projects"]
        case .codex: ["~/.codex/sessions"]
        default: []
        }
    }

    private static func recentSessionActivity(for provider: ProviderID, now: Date) -> Bool {
        let fileManager = FileManager.default
        return sessionRoots(for: provider).contains { root in
            let path = NSString(string: root).expandingTildeInPath
            guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return false }
            return enumerator.lazy.compactMap { item -> Date? in
                guard let file = item as? URL, file.pathExtension == "jsonl" || file.pathExtension == "json" else { return nil }
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
                return values.contentModificationDate
            }.contains { now.timeIntervalSince($0) < 5 }
        }
    }

    private static func recentApprovalEvidence(for provider: ProviderID, now: Date) -> Bool {
        let roots: [String]
        switch provider {
        case .claude:
            roots = ["~/.claude/projects"]
        case .codex:
            roots = ["~/.codex/sessions"]
        default:
            return false
        }
        let fileManager = FileManager.default
        for root in roots {
            let path = NSString(string: root).expandingTildeInPath
            guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in enumerator {
                guard file.pathExtension == "jsonl" || file.pathExtension == "json",
                      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) < 60,
                      let data = try? Data(contentsOf: file),
                      let text = String(data: Data(data.suffix(8_192)), encoding: .utf8)?.lowercased()
                else { continue }
                if ["action required", "permission", "approval", "allow command", "do you want to proceed", "waiting for input"].contains(where: { text.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private static func moreUrgent(_ current: AgentActivity?, _ candidate: AgentActivity) -> AgentActivity {
        guard let current else { return candidate }
        let priority: [AgentActivity: Int] = [.needsAction: 3, .working: 2, .idle: 1, .done: 0, .unknown: 0]
        return priority[candidate, default: 0] > priority[current, default: 0] ? candidate : current
    }
}
