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
        if remainingPercent <= 25 {
            return Color(red: 1.0, green: 0.32, blue: 0.15) // Low remaining: Vibrant coral/orange-red #FF5226
        } else if remainingPercent <= 50 {
            return Color(red: 0.82, green: 0.94, blue: 0.15) // Moderate remaining: Vibrant lime/yellow #D1F026
        } else {
            return Color(red: 0.18, green: 0.85, blue: 0.45) // Healthy remaining: Vibrant emerald green #2ED973
        }
    }

    var gradient: LinearGradient {
        if remainingPercent <= 25 {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.42, blue: 0.20), Color(red: 1.0, green: 0.22, blue: 0.10)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if remainingPercent <= 50 {
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

enum NotchPosition: String, CaseIterable, Identifiable, Sendable {
    case leftCenter
    case right
    case bottomCenter

    var id: Self { self }

    var title: String {
        switch self {
        case .leftCenter: "Left"
        case .right: "Right"
        case .bottomCenter: "Bottom"
        }
    }
}

enum UsageDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case remaining
    case used

    var id: Self { self }

    var title: String {
        switch self {
        case .remaining: "Remaining"
        case .used: "Used"
        }
    }
}

enum OverlayDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case alwaysExpanded
    case hover
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .alwaysExpanded: "Always show"
        case .hover: "Show on hover"
        case .hidden: "Hide"
        }
    }
}

enum ProviderIconShape: String, CaseIterable, Identifiable, Sendable {
    case circle
    case squircle
    case rounded
    case square

    var id: Self { self }

    var title: String {
        switch self {
        case .circle: "Circle"
        case .squircle: "Squircle"
        case .rounded: "Rounded"
        case .square: "Square"
        }
    }
}

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, openCode, openCodeGo, chatGPT, cursor, copilot, antigravity, xai, grok, groq, zai, clinePass

    static let allCases: [Self] = [
        .codex, .claude, .openCode, .chatGPT, .cursor, .copilot,
        .antigravity, .xai, .grok, .groq, .zai, .clinePass
    ]

    static let supported: [Self] = [
        .codex, .claude, .openCode, .zai, .grok, .xai, .cursor, .copilot, .antigravity, .clinePass
    ]

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
        case .zai: "Z.ai"
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
        case .zai: "z.circle"
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
        case .xai: "xai.svg"
        case .grok: "grok.svg"
        case .groq: "groq.svg"
        case .zai: "zai.svg"
        case .clinePass: "cline.svg"
        }
    }
}

enum ThemeColor: String, CaseIterable, Identifiable, Sendable {
    case rainbow, skyBlue, blue, purple, pink, red, orange, yellow, green, gray

    var id: Self { self }

    var title: String {
        switch self {
        case .rainbow: "Rainbow"
        case .skyBlue: "Sky blue"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .gray: "Gray"
        }
    }

    var color: Color {
        switch self {
        case .rainbow: .clear
        case .skyBlue: Color(red: 0.28, green: 0.72, blue: 0.98)
        case .blue: Color(red: 0.08, green: 0.48, blue: 1)
        case .purple: Color(red: 0.58, green: 0.25, blue: 0.68)
        case .pink: Color(red: 0.95, green: 0.22, blue: 0.56)
        case .red: Color(red: 1, green: 0.25, blue: 0.28)
        case .orange: Color(red: 1, green: 0.45, blue: 0.05)
        case .yellow: Color(red: 1, green: 0.72, blue: 0.02)
        case .green: Color(red: 0.32, green: 0.72, blue: 0.24)
        case .gray: Color(white: 0.56)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .rainbow: .clear
        default: NSColor(color)
        }
    }

    var solidColor: Color {
        switch self {
        case .rainbow: Color.black
        case .skyBlue: Color(red: 0.04, green: 0.15, blue: 0.22)
        case .blue: Color(red: 0.05, green: 0.12, blue: 0.22)
        case .purple: Color(red: 0.15, green: 0.07, blue: 0.19)
        case .pink: Color(red: 0.20, green: 0.05, blue: 0.12)
        case .red: Color(red: 0.22, green: 0.04, blue: 0.05)
        case .orange: Color(red: 0.22, green: 0.09, blue: 0.02)
        case .yellow: Color(red: 0.20, green: 0.15, blue: 0.02)
        case .green: Color(red: 0.05, green: 0.16, blue: 0.07)
        case .gray: Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }

    var solidNSColor: NSColor { NSColor(solidColor) }
}

enum WindowStyle: String, CaseIterable, Identifiable, Sendable {
    case liquidGlass, translucent, solid

    var id: Self { self }
    var title: String {
        switch self {
        case .liquidGlass: "Liquid glass"
        case .translucent: "Translucent"
        case .solid: "Solid"
        }
    }
}

enum AppSettings {
    static let notchPositionKey = "nootch.notchPosition"
    static let animationDurationKey = "nootch.animationDuration"
    static let activityAnimationDurationKey = "nootch.activityAnimationDuration"
    static let overlayDisplayModeKey = "nootch.overlayDisplayMode"
    static let usageDisplayModeKey = "nootch.usageDisplayMode"
    static let showInDockKey = "nootch.showInDock"
    static let launchAtLoginKey = "nootch.launchAtLogin"
    static let providerIconShapeKey = "nootch.providerIconShape"
    static let themeColorKey = "nootch.themeColor"
    static let windowStyleKey = "nootch.windowStyle"
    @MainActor static var activeWindowStyle: WindowStyle = .liquidGlass

    // Keep legacy names only for importing preferences from earlier releases.
    static func migrateLegacyPreferences(
        defaults: UserDefaults = .standard,
        legacyDomainNames: [String] = ["com.deepanshumishraa.agentnotch", "AgentNotch"]
    ) {
        let migrationKey = "nootch.preferencesMigrated.v1"
        guard !defaults.bool(forKey: migrationKey) else { return }
        let domains = [defaults.dictionaryRepresentation()] + legacyDomainNames.compactMap {
            defaults.persistentDomain(forName: $0)
        }
        for domain in domains {
            for (key, value) in domain where key.hasPrefix("UsageNotch.") {
                let newKey = "nootch." + key.dropFirst("UsageNotch.".count)
                if defaults.object(forKey: newKey) == nil {
                    defaults.set(value, forKey: newKey)
                }
            }
        }
        defaults.set(true, forKey: migrationKey)
    }

    @MainActor static func configure() {
        migrateLegacyPreferences()
        let saved = WindowStyle(rawValue: UserDefaults.standard.string(forKey: windowStyleKey) ?? "") ?? .liquidGlass
        if #available(macOS 26.0, *) {
            activeWindowStyle = saved
        } else {
            activeWindowStyle = saved == .liquidGlass ? .translucent : saved
        }
    }

    static let providerEnabledPrefix = "nootch.providerEnabled."

    static var currentTheme: ThemeColor {
        ThemeColor(rawValue: UserDefaults.standard.string(forKey: themeColorKey) ?? "") ?? .red
    }

    static var usageDisplayMode: UsageDisplayMode {
        UsageDisplayMode(rawValue: UserDefaults.standard.string(forKey: usageDisplayModeKey) ?? "") ?? .remaining
    }

    static var overlayDisplayMode: OverlayDisplayMode {
        OverlayDisplayMode(rawValue: UserDefaults.standard.string(forKey: overlayDisplayModeKey) ?? "") ?? .hover
    }

    static var providerIconShape: ProviderIconShape {
        ProviderIconShape(rawValue: UserDefaults.standard.string(forKey: providerIconShapeKey) ?? "") ?? .circle
    }

    static var animationDuration: Double {
        let value = UserDefaults.standard.double(forKey: animationDurationKey)
        return value == 0 ? 0.32 : value
    }

    static var activityAnimationDuration: Double {
        let value = UserDefaults.standard.double(forKey: activityAnimationDurationKey)
        return value == 0 ? 1.6 : value
    }

    static func isProviderEnabled(_ provider: ProviderID) -> Bool {
        let key = providerEnabledPrefix + provider.rawValue
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}

struct CostUsageSummary: Sendable, Equatable, Codable {
    let todayTokens: Int?
    let todayCostUSD: Double?
    let last30DaysTokens: Int?
    let last30DaysCostUSD: Double?
    let historyAvailable: Bool

    static func unavailable() -> Self {
        Self(todayTokens: nil, todayCostUSD: nil, last30DaysTokens: nil, last30DaysCostUSD: nil, historyAvailable: false)
    }
}

enum AgentActivity: String, Codable, Sendable, Equatable {
    case working
    case needsAction
    case done
    case idle
    case unknown

    var isWorking: Bool { self == .working }
    var needsAttention: Bool { self == .needsAction }
}

struct ProviderStatus: Identifiable, Sendable, Equatable, Codable {
    let provider: ProviderID
    let detected: Bool
    let source: String?
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let error: String?
    let updatedAt: Date?
    let costUsage: CostUsageSummary?
    let activity: AgentActivity
    var id: ProviderID { provider }

    init(
        provider: ProviderID,
        detected: Bool,
        source: String?,
        primary: UsageWindow?,
        secondary: UsageWindow?,
        error: String?,
        updatedAt: Date?,
        costUsage: CostUsageSummary? = nil,
        activity: AgentActivity = .unknown)
    {
        self.provider = provider
        self.detected = detected
        self.source = source
        self.primary = primary
        self.secondary = secondary
        self.error = error
        self.updatedAt = updatedAt
        self.costUsage = costUsage
        self.activity = activity
    }

    enum CodingKeys: String, CodingKey {
        case provider, detected, source, primary, secondary, error, updatedAt, costUsage, activity
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            provider: try values.decode(ProviderID.self, forKey: .provider),
            detected: try values.decode(Bool.self, forKey: .detected),
            source: try values.decodeIfPresent(String.self, forKey: .source),
            primary: try values.decodeIfPresent(UsageWindow.self, forKey: .primary),
            secondary: try values.decodeIfPresent(UsageWindow.self, forKey: .secondary),
            error: try values.decodeIfPresent(String.self, forKey: .error),
            updatedAt: try values.decodeIfPresent(Date.self, forKey: .updatedAt),
            costUsage: try values.decodeIfPresent(CostUsageSummary.self, forKey: .costUsage),
            activity: try values.decodeIfPresent(AgentActivity.self, forKey: .activity) ?? .unknown)
    }

    func withActivity(_ activity: AgentActivity) -> Self {
        Self(provider: provider, detected: detected, source: source, primary: primary, secondary: secondary, error: error, updatedAt: updatedAt, costUsage: costUsage, activity: activity)
    }

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
