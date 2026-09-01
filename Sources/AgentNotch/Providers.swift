import Foundation

struct ProviderDiscovery: Sendable {
    private let adapters: [any ProviderAdapter]

    init(adapters: [any ProviderAdapter] = ProviderDiscovery.defaultAdapters) {
        self.adapters = adapters
    }

    func discover() async -> [ProviderStatus] {
        await withTaskGroup(of: ProviderStatus.self, returning: [ProviderStatus].self) { group in
            for adapter in adapters {
                group.addTask {
                    let detection = await adapter.detect()
                    return .unavailable(adapter.provider, detected: detection.detected, source: detection.source)
                }
            }
            var result: [ProviderStatus] = []
            for await status in group { result.append(status) }
            return result.sorted { $0.provider.name < $1.provider.name }
        }
    }

    static let defaultAdapters: [any ProviderAdapter] = [
        CodexAdapter(),
        ClaudeAdapter(),
        OpenCodeAdapter(),
        ClinePassAdapter(),
        AntigravityAdapter(),
        CursorAdapter(),
        CopilotAdapter()
    ]
}

struct FileProviderAdapter: ProviderAdapter {
    let provider: ProviderID
    let files: [String]
    let directories: [String]
    let applicationPaths: [String]
    let command: String?

    init(
        provider: ProviderID,
        files: [String] = [],
        directories: [String] = [],
        applicationPaths: [String] = [],
        command: String? = nil)
    {
        self.provider = provider
        self.files = files
        self.directories = directories
        self.applicationPaths = applicationPaths
        self.command = command
    }

    func detect() async -> DetectionResult {
        let fileManager = FileManager.default
        for path in files {
            let expanded = NSString(string: path).expandingTildeInPath
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), !isDirectory.boolValue {
                return DetectionResult(detected: true, source: path)
            }
        }
        for path in directories {
            let expanded = NSString(string: path).expandingTildeInPath
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return DetectionResult(detected: true, source: path)
            }
        }
        for path in applicationPaths {
            let expanded = NSString(string: path).expandingTildeInPath
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return DetectionResult(detected: true, source: path)
            }
        }
        if let command, Self.commandExists(command) {
            return DetectionResult(detected: true, source: "\(command) CLI")
        }
        return DetectionResult(detected: false, source: nil)
    }

    func fetch() async -> ProviderStatus {
        let detection = await detect()
        guard detection.detected else { return .unavailable(provider, detected: false) }
        return .unavailable(
            provider,
            detected: true,
            source: detection.source,
            error: "Usage source not configured yet")
    }

    private static func commandExists(_ command: String) -> Bool {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return paths.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(command)") }
    }
}
