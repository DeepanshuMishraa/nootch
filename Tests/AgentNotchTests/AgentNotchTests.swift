import Foundation
import Testing
@testable import AgentNotch

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
