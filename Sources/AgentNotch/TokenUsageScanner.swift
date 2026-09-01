import Foundation

enum TokenUsageScanner {
    static func scanCodex(now: Date = Date(), calendar: Calendar = .current) -> CostUsageSummary {
        let codex = scanCodexSessions(now: now, calendar: calendar)
        let pi = scanPiSessions(now: now, calendar: calendar)
        return merge(codex, pi)
    }

    static func scanClaude(now: Date = Date(), calendar: Calendar = .current) -> CostUsageSummary {
        let root = NSString(string: "~/.claude/projects").expandingTildeInPath
        return scanJSONLines(root: root, now: now, calendar: calendar) { object in
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { return nil }
            let input = integer(usage["input_tokens"])
            let cached = integer(usage["cache_read_input_tokens"])
            let created = integer(usage["cache_creation_input_tokens"])
            let output = integer(usage["output_tokens"])
            let model = (message["model"] as? String)?.lowercased() ?? ""
            let inputRate = model.contains("opus") ? 15.0e-6 : model.contains("haiku") ? 0.8e-6 : 3.0e-6
            let outputRate = model.contains("opus") ? 75.0e-6 : model.contains("haiku") ? 4.0e-6 : 15.0e-6
            let cacheRate = model.contains("opus") ? 1.5e-6 : model.contains("haiku") ? 0.08e-6 : 0.3e-6
            let cost = Double(input) * inputRate + Double(output) * outputRate + Double(cached + created) * cacheRate
            return (input + cached + created + output, cost)
        }
    }

    private static func scanCodexSessions(now: Date, calendar: Calendar) -> CostUsageSummary {
        let root = NSString(string: "~/.codex/sessions").expandingTildeInPath
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return .unavailable() }

        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return .unavailable() }
        var result = Totals()

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var previousCumulative = 0
            var model: String?
            var priority = false

            for line in content.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let payload = object["payload"] as? [String: Any] ?? [:]
                if object["type"] as? String == "turn_context" {
                    model = payload["model"] as? String ?? model
                    continue
                }
                if payload["type"] as? String == "thread_settings_applied" {
                    model = payload["model"] as? String ?? model
                    priority = payload["service_tier"] as? String == "priority"
                    continue
                }
                guard payload["type"] as? String == "token_count",
                      let timestamp = (object["timestamp"] as? String).flatMap(parseDate),
                      let info = payload["info"] as? [String: Any],
                      let cumulative = info["total_token_usage"] as? [String: Any]
                else { continue }

                let cumulativeTokens = integer(cumulative["input_tokens"]) + integer(cumulative["output_tokens"])
                let delta = max(0, cumulativeTokens - previousCumulative)
                previousCumulative = max(previousCumulative, cumulativeTokens)
                guard timestamp >= start, delta > 0 else { continue }

                let estimatedCost = (info["last_token_usage"] as? [String: Any]).flatMap {
                    codexCost(usage: $0, acceptedTokens: delta, model: model, priority: priority)
                }
                result.add(tokens: delta, cost: estimatedCost, timestamp: timestamp, today: today)
            }
        }
        return result.summary
    }

    private static func scanPiSessions(now: Date, calendar: Calendar) -> CostUsageSummary {
        let root = NSString(string: "~/.pi/agent/sessions").expandingTildeInPath
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return .unavailable() }

        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return .unavailable() }
        var result = Totals()

        for case let url as URL in enumerator where url.pathExtension == "jsonl" && !url.lastPathComponent.hasSuffix("_transcript.jsonl") {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let message = object["message"] as? [String: Any] ?? [:]
                let provider = message["provider"] as? String ?? object["provider"] as? String
                guard provider == "openai-codex",
                      let usage = object["usage"] as? [String: Any] ?? message["usage"] as? [String: Any],
                      let timestamp = timestamp(from: object["timestamp"] ?? message["timestamp"]),
                      timestamp >= start
                else { continue }

                let total = integer(usage["totalTokens"])
                let tokens = total > 0 ? total : ["input", "output", "cacheRead", "cacheWrite"].reduce(0) {
                    $0 + integer(usage[$1])
                }
                let costValue = usage["cost"]
                let cost: Double? = if let value = number(costValue) {
                    value
                } else if let values = costValue as? [String: Any] {
                    number(values["total"])
                } else {
                    nil
                }
                result.add(tokens: tokens, cost: cost, timestamp: timestamp, today: today)
            }
        }
        return result.summary
    }

    private static func codexCost(
        usage: [String: Any],
        acceptedTokens: Int,
        model: String?,
        priority: Bool) -> Double?
    {
        let input = integer(usage["input_tokens"])
        let cached = min(input, integer(usage["cached_input_tokens"] ?? usage["cache_read_input_tokens"]))
        let output = integer(usage["output_tokens"])
        let reportedTokens = input + output
        guard reportedTokens > 0, let model else { return nil }
        let aboveThreshold = input > 272_000
        let rates: (input: Double, cached: Double, output: Double)? = switch (model, aboveThreshold) {
        case ("gpt-5.6-luna", false): (0.2, 0.02, 1.2)
        case ("gpt-5.6-luna", true): (0.4, 0.04, 1.8)
        case ("gpt-5.6-sol", false): (5, 0.5, 30)
        case ("gpt-5.6-sol", true): (10, 1, 45)
        default: nil
        }
        guard let rates else { return nil }
        let scale = min(1, Double(acceptedTokens) / Double(reportedTokens))
        let multiplier = priority ? 2.0 : 1.0
        return (Double(input - cached) * rates.input + Double(cached) * rates.cached + Double(output) * rates.output)
            * scale * multiplier / 1_000_000
    }

    private static func merge(_ first: CostUsageSummary, _ second: CostUsageSummary) -> CostUsageSummary {
        guard first.historyAvailable || second.historyAvailable else { return .unavailable() }
        return CostUsageSummary(
            todayTokens: sum(first.todayTokens, second.todayTokens),
            todayCostUSD: sum(first.todayCostUSD, second.todayCostUSD),
            last30DaysTokens: sum(first.last30DaysTokens, second.last30DaysTokens),
            last30DaysCostUSD: sum(first.last30DaysCostUSD, second.last30DaysCostUSD),
            historyAvailable: true)
    }

    private static func sum(_ first: Int?, _ second: Int?) -> Int? {
        guard first != nil || second != nil else { return nil }
        return (first ?? 0) + (second ?? 0)
    }

    private static func sum(_ first: Double?, _ second: Double?) -> Double? {
        guard first != nil || second != nil else { return nil }
        return (first ?? 0) + (second ?? 0)
    }

    private struct Totals {
        var todayTokens = 0
        var todayCost = 0.0
        var historyTokens = 0
        var historyCost = 0.0
        var rows = 0
        var unknownCost = false

        mutating func add(tokens: Int, cost: Double?, timestamp: Date, today: Date) {
            rows += 1
            historyTokens += tokens
            if timestamp >= today { todayTokens += tokens }
            if let cost {
                historyCost += cost
                if timestamp >= today { todayCost += cost }
            } else {
                unknownCost = true
            }
        }

        var summary: CostUsageSummary {
            guard rows > 0 else { return .unavailable() }
            return CostUsageSummary(
                todayTokens: todayTokens,
                todayCostUSD: unknownCost ? nil : todayCost,
                last30DaysTokens: historyTokens,
                last30DaysCostUSD: unknownCost ? nil : historyCost,
                historyAvailable: true)
        }
    }

    private static func scanJSONLines(
        root: String,
        now: Date,
        calendar: Calendar,
        parse: ([String: Any]) -> (Int, Double?)?) -> CostUsageSummary
    {
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return .unavailable()
        }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return .unavailable() }
        var result = Totals()
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = (object["timestamp"] as? String).flatMap(parseDate),
                      timestamp >= start,
                      let row = parse(object)
                else { continue }
                result.add(tokens: row.0, cost: row.1, timestamp: timestamp, today: today)
            }
        }
        return result.summary
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func timestamp(from value: Any?) -> Date? {
        if let value = value as? String { return parseDate(value) }
        if let value = number(value) {
            return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1_000 : value)
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
