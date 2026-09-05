import Foundation
import Testing
@testable import Nootch

@Test func remainingPercentageIsDerivedFromUsedPercentage() {
    let window = UsageWindow(usedPercent: 73)
    #expect(window.remainingPercent == 27)
}

@Test func remainingPercentageInputIsConvertedToUsedPercentage() {
    let window = UsageWindow.fromRemainingPercent(21, windowMinutes: 300)
    #expect(window.usedPercent == 79)
    #expect(window.windowMinutes == 300)
}

@Test func percentageIsClampedAtTheBoundary() {
    #expect(UsageWindow(usedPercent: -5).usedPercent == 0)
    #expect(UsageWindow(usedPercent: 105).usedPercent == 100)
}

@Test func agentActivityClassifiesWorkingAndIdleFromProcessActivity() {
    #expect(AgentActivityDetector.classify(cpu: 1.0, approvalEvidence: false) == .working)
    #expect(AgentActivityDetector.classify(cpu: 0.1, processState: "S+", recentActivity: true, approvalEvidence: false) == .working)
    #expect(AgentActivityDetector.classify(cpu: 0.1, processState: "R+", approvalEvidence: false) == .working)
    #expect(AgentActivityDetector.classify(cpu: 0.1, approvalEvidence: false) == .idle)
}

@Test func agentActivityPrioritizesNeedsActionOverProcessActivity() {
    #expect(AgentActivityDetector.classify(cpu: 8.0, approvalEvidence: true) == .needsAction)
}

@Test func agentActivityDetectorMapsKnownProcessesWithoutHerdr() {
    let detector = AgentActivityDetector {
        "101 codex 0.1 S+ codex\n102 claude 4.0 R+ claude\n103 bash 0.0 S+ bash"
    }
    let snapshot = detector.snapshot()
    #expect(snapshot.isReliable)
    #expect(snapshot.activityByProvider[.codex] == .idle)
    #expect(snapshot.activityByProvider[.claude] == .working)
    #expect(AgentActivityDetector.provider(for: "/Applications/Codex.app/Contents/MacOS/Codex") == .codex)
    #expect(AgentActivityDetector.provider(for: "node", arguments: "/Applications/Cursor.app/Contents/Resources/app/out/agent.js") == .cursor)
    #expect(snapshot.activityByProvider[.openCode] == nil)
}

@Test func agentActivityDetectorDoesNotInventStateWhenProcessProbeFails() {
    let snapshot = AgentActivityDetector { "" }.snapshot()
    #expect(!snapshot.isReliable)
    #expect(snapshot.activityByProvider.isEmpty)
}

private func testStatus(_ provider: ProviderID, activity: AgentActivity) -> ProviderStatus {
    ProviderStatus(provider: provider, detected: true, source: "test", primary: nil, secondary: nil, error: nil, updatedAt: nil, activity: activity)
}

@Test func mergedActivityReturnsNilWhenSnapshotIsUnreliable() {
    let statuses = [testStatus(.codex, activity: .working)]
    let snapshot = AgentActivitySnapshot(activityByProvider: [.codex: .idle], isReliable: false)
    #expect(UsageStore.mergedActivity(statuses, with: snapshot) == nil)
}

@Test func mergedActivityReturnsNilWhenNothingChanged() {
    let statuses = [testStatus(.codex, activity: .working), testStatus(.claude, activity: .done)]
    let snapshot = AgentActivitySnapshot(activityByProvider: [.codex: .working], isReliable: true)
    // Absent providers project to .done, which already matches here.
    #expect(UsageStore.mergedActivity(statuses, with: snapshot) == nil)
}

@Test func mergedActivityReturnsMergedArrayOnlyOnChange() {
    let statuses = [testStatus(.codex, activity: .idle)]
    let snapshot = AgentActivitySnapshot(activityByProvider: [.codex: .working], isReliable: true)
    let merged = UsageStore.mergedActivity(statuses, with: snapshot)
    #expect(merged?.first?.activity == .working)
    #expect(statuses.first?.activity == .idle)
}

@Test @MainActor func hasActiveActivityMatchesVisibleActivity() {
    let store = UsageStore(adapters: [], activityDetector: AgentActivityDetector { "" })
    let expected = store.statuses.contains { $0.activity.isWorking || $0.activity.needsAttention }
    #expect(store.hasActiveActivity == expected)
}

@Test func mouseMoveThrottleCoalescesRapidEvents() {    let throttle = MouseMoveThrottle()
    let start = Date()
    let origin = NSPoint(x: 100, y: 100)
    #expect(throttle.shouldHandle(at: origin, now: start))
    // Same location immediately after: dropped (no new Task / MainActor hop).
    #expect(!throttle.shouldHandle(at: origin, now: start.addingTimeInterval(0.01)))
    // Far enough but too soon: still dropped.
    #expect(!throttle.shouldHandle(at: NSPoint(x: 500, y: 500), now: start.addingTimeInterval(0.01)))
    // Small jitter after the interval: dropped.
    #expect(!throttle.shouldHandle(at: NSPoint(x: 101, y: 100), now: start.addingTimeInterval(0.2)))
    // Real movement after the interval: handled.
    #expect(throttle.shouldHandle(at: NSPoint(x: 200, y: 200), now: start.addingTimeInterval(0.2)))
}

@Test func scanClaudeMemoizesUnchangedTreesAndPicksUpAppends() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let line = #"{"timestamp":"2026-09-05T10:00:00Z","message":{"model":"sonnet","usage":{"input_tokens":100,"output_tokens":20}}}"# + "\n"
    let url = root.appendingPathComponent("session.jsonl")
    try String(repeating: line, count: 100).write(to: url, atomically: true, encoding: .utf8)
    let now = Date(timeIntervalSince1970: 1_788_609_600)
    let first = TokenUsageScanner.scanClaude(now: now, root: root.path)
    #expect(first.last30DaysTokens == 12_000)
    // Unchanged tree: same totals without re-parsing.
    let second = TokenUsageScanner.scanClaude(now: now, root: root.path)
    #expect(second == first)
    // Appended row changes size/mtime: rescan picks it up.
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(line.utf8))
    try handle.close()
    let third = TokenUsageScanner.scanClaude(now: now, root: root.path)
    #expect(third.last30DaysTokens == 12_120)
}

@Test func scanClaudeHandlesFilesLargerThanCompactionThreshold() throws {
    // The row reader compacts its buffer past 1MB; Data indices are not
    // zero-based after removeFirst, so this must still parse every row.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let filler = String(repeating: "x", count: 2048)
    let line = #"{"timestamp":"2026-09-05T10:00:00Z","message":{"model":"sonnet","usage":{"input_tokens":10,"output_tokens":5}},"pad":""# + filler + "\"}\n"
    let count = 1200
    try String(repeating: line, count: count).write(to: root.appendingPathComponent("big.jsonl"), atomically: true, encoding: .utf8)
    let summary = TokenUsageScanner.scanClaude(now: Date(timeIntervalSince1970: 1_788_609_600), root: root.path)
    #expect(summary.last30DaysTokens == count * 15)
}
