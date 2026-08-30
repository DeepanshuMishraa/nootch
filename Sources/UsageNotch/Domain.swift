import Foundation
import SwiftUI

struct UsageWindow: Codable, Sendable, Equatable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    init(usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.usedPercent = min(100, max(0, usedPercent))
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    static func fromRemainingPercent(_ remaining: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) -> Self {
        Self(usedPercent: 100 - remaining, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }

    var tierColor: Color {
        if remainingPercent < 40 {
            return Color(red: 1.0, green: 0.32, blue: 0.15) // Low remaining: Vibrant coral/orange-red #FF5226
        } else if remainingPercent < 70 {
            return Color(red: 0.82, green: 0.94, blue: 0.15) // Moderate remaining: Vibrant lime/yellow #D1F026
        } else {
            return Color(red: 0.18, green: 0.85, blue: 0.45) // Healthy remaining: Vibrant emerald green #2ED973
        }
    }

    var gradient: LinearGradient {
        if remainingPercent < 40 {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.42, blue: 0.20), Color(red: 1.0, green: 0.22, blue: 0.10)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if remainingPercent < 70 {
            return LinearGradient(
                colors: [Color(red: 0.88, green: 0.98, blue: 0.22), Color(red: 0.74, green: 0.88, blue: 0.12)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 0.22, green: 0.88, blue: 0.52), Color(red: 0.14, green: 0.78, blue: 0.38)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    var resetsInCountdown: String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSinceNow
        if interval <= 0 { return "Resets soon" }
        let totalMinutes = Int(ceil(interval / 60))
        if totalMinutes < 60 {
            return "Resets in \(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 24 {
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? "Resets in \(days)d \(remHours)h" : "Resets in \(days)d"
    }

    var formattedAbsoluteReset: String? {
        guard let resetsAt else { return nil }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(resetsAt) {
            formatter.dateFormat = "'today' h:mm a"
            return "Resets \(formatter.string(from: resetsAt))"
        } else if calendar.isDateInTomorrow(resetsAt) {
            formatter.dateFormat = "'tomorrow' h:mm a"
            return "Resets \(formatter.string(from: resetsAt))"
        } else {
            formatter.dateFormat = "EEE h:mm a"
            return "Resets \(formatter.string(from: resetsAt))"
        }
    }
}

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, openCode, openCodeGo, chatGPT, cursor, copilot, antigravity, xai, grok, groq, clinePass
    var id: Self { self }
    var name: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .openCode: "OpenCode"
        case .openCodeGo: "OpenCode Go"
        case .chatGPT: "ChatGPT"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .antigravity: "Antigravity"
        case .xai: "xAI"
        case .grok: "Grok"
        case .groq: "Groq"
        case .clinePass: "ClinePass"
        }
    }
    var icon: String {
        switch self {
        case .codex, .chatGPT: "circle.hexagongrid.fill"
        case .claude: "sparkles"
        case .openCode, .openCodeGo: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .copilot: "airplane"
        case .antigravity: "sparkles"
        case .xai, .grok: "bolt.fill"
        case .groq: "chart.xyaxis.line"
        case .clinePass: "circle.hexagonpath.fill"
        }
    }
    var logoResource: String? {
        switch self {
        case .codex, .chatGPT: "openai.svg"
        case .claude: "claude.svg"
        case .copilot: "copilot.svg"
        case .antigravity: "antigravity.svg"
        case .cursor: "cursor.svg"
        case .openCode, .openCodeGo: "opencode.svg"
        case .xai, .grok, .groq, .clinePass: nil
        }
    }
}

struct ProviderStatus: Identifiable, Sendable, Equatable, Codable {
    let provider: ProviderID
    let detected: Bool
    let source: String?
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let error: String?
    let updatedAt: Date?
    var id: ProviderID { provider }

    static func unavailable(_ provider: ProviderID, detected: Bool, source: String? = nil, error: String? = nil) -> Self {
        Self(provider: provider, detected: detected, source: source, primary: nil, secondary: nil, error: error, updatedAt: nil)
    }
}

protocol ProviderAdapter: Sendable {
    var provider: ProviderID { get }
    func detect() async -> DetectionResult
    func fetch() async -> ProviderStatus
}

struct DetectionResult: Sendable, Equatable {
    let detected: Bool
    let source: String?
}
