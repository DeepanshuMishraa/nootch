import AppKit
import SwiftUI
import Testing
@testable import AgentNotch

// Opt-in local probes. Never launch AppDelegate, read credentials, or fetch live usage.
struct PerformanceSample {
    let wall = Date()
    let cpu: Double
    let resident: UInt64
    let peak: Int

    init() {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        peak = usage.ru_maxrss
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        resident = result == KERN_SUCCESS ? info.resident_size : 0
    }

    func report(_ label: String, since start: Self) {
        let elapsed = wall.timeIntervalSince(start.wall)
        print(String(format: "PERF %@ wall=%.3fs cpu=%.2f%% rss=%.1fMiB peak=%.1fMiB", label,
                     elapsed, (cpu - start.cpu) / elapsed * 100,
                     Double(resident) / 1_048_576, Double(peak) / 1_048_576))
    }
}

@Test func profileSyntheticHistory() throws {
    guard ProcessInfo.processInfo.environment["AGENT_NOTCH_PROFILE"] == "scan" else { return }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let line = #"{"timestamp":"2026-09-05T10:00:00Z","message":{"model":"claude-sonnet","usage":{"input_tokens":100,"output_tokens":20},"content":""}}"#
    // 100,000 valid rows, roughly 60MB with irrelevant message text.
    let row = line.replacingOccurrences(of: #""content":"""#, with: #""content":""# + String(repeating: "x", count: 512) + #"""#) + "\n"
    try String(repeating: row, count: 100_000).write(to: root.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    let now = Date(timeIntervalSince1970: 1_788_609_600)
    for index in 0..<3 {
        let start = PerformanceSample()
        let summary = TokenUsageScanner.scanClaude(now: now, root: root.path)
        #expect(summary.last30DaysTokens == 12_000_000)
        PerformanceSample().report("scan-\(index)", since: start)
    }
}

@Test @MainActor func profileSyntheticRail() async throws {
    guard let mode = ProcessInfo.processInfo.environment["AGENT_NOTCH_PROFILE"], mode == "rail" else { return }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 100, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let status = ProviderStatus(provider: .claude, detected: true, source: "Synthetic", primary: UsageWindow(usedPercent: 20), secondary: nil, error: nil, updatedAt: nil, activity: ProcessInfo.processInfo.environment["AGENT_NOTCH_ACTIVITY"] == "idle" ? .idle : .working)
    window.contentView = NSHostingView(rootView: VStack {
        ForEach(0..<4) { _ in ProviderRailItem(status: status, isHovered: false).frame(width: 72, height: 76) }
    })
    window.orderFrontRegardless()
    for index in 0..<3 {
        let start = PerformanceSample()
        try await Task.sleep(for: .seconds(5))
        PerformanceSample().report("rail-\(index)", since: start)
    }
}
