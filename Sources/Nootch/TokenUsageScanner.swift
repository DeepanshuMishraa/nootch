import Foundation
import Synchronization

enum TokenUsageScanner {
    static func scanCodex(now: Date = Date(), calendar: Calendar = .current) -> CostUsageSummary {
        let codexRoot = NSString(string: "~/.codex/sessions").expandingTildeInPath
        let piRoot = NSString(string: "~/.pi/agent/sessions").expandingTildeInPath
        // Quota refreshes run every 30s and call this synchronously. Re-parsing
        // ~775MB of JSONL each time pegged multiple cores, so return the cached
        // summary when no session file changed (one stat-only enumeration).
        let key = SummaryCacheKey(kind: "codex", today: calendar.startOfDay(for: now))
        let fingerprint = Self.fingerprint(roots: [
            (codexRoot, { Self.isCodexHistory($0) }),
            (piRoot, { Self.isPiHistory($0) }),
        ])
        return Self.memoizedSummary(key: key, fingerprint: fingerprint) {
            let codex = scanCodexSessions(now: now, calendar: calendar)
            let pi = scanPiSessions(now: now, calendar: calendar)
            return merge(codex, pi)
        }
    }

    static func scanClaude(
        now: Date = Date(),
        calendar: Calendar = .current,
        root: String = NSString(string: "~/.claude/projects").expandingTildeInPath) -> CostUsageSummary
    {
        let key = SummaryCacheKey(kind: "claude:\(root)", today: calendar.startOfDay(for: now))
        let fingerprint = Self.fingerprint(roots: [(root, { $0.pathExtension == "jsonl" })])
        return Self.memoizedSummary(key: key, fingerprint: fingerprint) {
            scanJSONLines(root: root, now: now, calendar: calendar) { object in
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
    }

    static func scanCodexSessions(now: Date, calendar: Calendar,
                                  root: String = NSString(string: "~/.codex/sessions").expandingTildeInPath) -> CostUsageSummary {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return .unavailable() }

        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return .unavailable() }
        var result = Totals()
        let dates = HistoryDates()

        for case let url as URL in enumerator where Self.isCodexHistory(url) {
            var previousCumulative = 0
            var model: String?
            var priority = false

            let fileTotals = cachedTotals(at: url, kind: "codex", today: today, calendar: calendar) {
                var totals = Totals()
                let completed = forEachHistoryRow(at: url) { object in
                    let payload = object["payload"] as? [String: Any] ?? [:]
                    if object["type"] as? String == "turn_context" {
                        model = payload["model"] as? String ?? model
                        return
                    }
                    if payload["type"] as? String == "thread_settings_applied" {
                        model = payload["model"] as? String ?? model
                        priority = payload["service_tier"] as? String == "priority"
                        return
                    }
                    guard payload["type"] as? String == "token_count",
                          let timestamp = (object["timestamp"] as? String).flatMap(dates.parse),
                          let info = payload["info"] as? [String: Any],
                          let cumulative = info["total_token_usage"] as? [String: Any]
                    else { return }

                    let cumulativeTokens = integer(cumulative["input_tokens"]) + integer(cumulative["output_tokens"])
                    let delta = max(0, cumulativeTokens - previousCumulative)
                    previousCumulative = max(previousCumulative, cumulativeTokens)
                    guard timestamp >= start, delta > 0 else { return }

                    let estimatedCost = (info["last_token_usage"] as? [String: Any]).flatMap {
                        codexCost(usage: $0, acceptedTokens: delta, model: model, priority: priority)
                    }
                    totals.add(tokens: delta, cost: estimatedCost, timestamp: timestamp, today: today)
                }
                return completed ? totals : nil
            }
            result.merge(fileTotals)
        }
        return result.summary
    }

    static func scanPiSessions(now: Date, calendar: Calendar,
                               root: String = NSString(string: "~/.pi/agent/sessions").expandingTildeInPath) -> CostUsageSummary {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return .unavailable() }

        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return .unavailable() }
        var result = Totals()
        let dates = HistoryDates()

        for case let url as URL in enumerator where Self.isPiHistory(url) {
            let fileTotals = cachedTotals(at: url, kind: "pi", today: today, calendar: calendar) {
                var totals = Totals()
                let completed = forEachHistoryRow(at: url) { object in
                    let message = object["message"] as? [String: Any] ?? [:]
                    let provider = message["provider"] as? String ?? object["provider"] as? String
                    guard provider == "openai-codex",
                          let usage = object["usage"] as? [String: Any] ?? message["usage"] as? [String: Any],
                          let timestamp = dates.timestamp(from: object["timestamp"] ?? message["timestamp"]),
                          timestamp >= start
                    else { return }

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
                    totals.add(tokens: tokens, cost: cost, timestamp: timestamp, today: today)
                }
                return completed ? totals : nil
            }
            result.merge(fileTotals)
        }
        return result.summary
    }

    private static func isCodexHistory(_ url: URL) -> Bool {
        url.pathExtension == "jsonl"
    }

    private static func isPiHistory(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && !url.lastPathComponent.hasSuffix("_transcript.jsonl")
    }

    private struct SummaryCacheKey: Hashable, Sendable {
        let kind: String
        let today: Date
    }

    private struct SummaryCacheEntry: Sendable {
        let fingerprint: UInt64
        let summary: CostUsageSummary
    }

    // Whole-summary memo: quota refreshes call the scanners every 30s.
    private static let summaryCache = Mutex<[SummaryCacheKey: SummaryCacheEntry]>([:])

    private struct DiskSummaryCacheEntry: Codable {
        let fingerprint: UInt64
        let summary: CostUsageSummary
    }

    private static func diskCacheKey(for key: SummaryCacheKey) -> String {
        "nootch.tokenSummary.\(key.kind).\(Int(key.today.timeIntervalSince1970))"
    }

    /// Returns the cached summary when the fingerprint matches, consulting the
    /// in-memory cache first and a UserDefaults entry second so even a fresh
    /// launch skips re-parsing gigabytes of unchanged session history.
    private static func memoizedSummary(
        key: SummaryCacheKey,
        fingerprint: UInt64?,
        compute: () -> CostUsageSummary
    ) -> CostUsageSummary {
        if let fingerprint {
            if let entry = summaryCache.withLock({ $0[key] }), entry.fingerprint == fingerprint {
                return entry.summary
            }
            if let data = UserDefaults.standard.data(forKey: diskCacheKey(for: key)),
               let entry = try? JSONDecoder().decode(DiskSummaryCacheEntry.self, from: data),
               entry.fingerprint == fingerprint {
                summaryCache.withLock { $0[key] = SummaryCacheEntry(fingerprint: fingerprint, summary: entry.summary) }
                return entry.summary
            }
        }
        let summary = compute()
        if let fingerprint,
           let data = try? JSONEncoder().encode(DiskSummaryCacheEntry(fingerprint: fingerprint, summary: summary)) {
            summaryCache.withLock { $0[key] = SummaryCacheEntry(fingerprint: fingerprint, summary: summary) }
            UserDefaults.standard.set(data, forKey: diskCacheKey(for: key))
        }
        return summary
    }

    /// Order-independent fingerprint over the matching files' paths, sizes and
    /// mtimes. Stat-only: no file contents are read. Any append/modification
    /// changes size or mtime, so an equal fingerprint means equal content for
    /// caching purposes.
    private static func fingerprint(roots: [(String, (URL) -> Bool)]) -> UInt64? {
        var combined: UInt64 = 0
        var count = 0
        var totalSize = 0
        for (root, matches) in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator {
                guard matches(url),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true
                else { continue }
                let size = values.fileSize ?? 0
                let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                var hasher = Hasher()
                hasher.combine(url.path)
                hasher.combine(size)
                hasher.combine(mtime)
                combined ^= UInt64(bitPattern: Int64(hasher.finalize()))
                count += 1
                totalSize += size
            }
        }
        var hasher = Hasher()
        hasher.combine(count)
        hasher.combine(totalSize)
        return combined ^ UInt64(bitPattern: Int64(hasher.finalize()))
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

    private struct Totals: Sendable {
        mutating func merge(_ other: Self) {
            todayTokens += other.todayTokens
            todayCost += other.todayCost
            historyTokens += other.historyTokens
            historyCost += other.historyCost
            rows += other.rows
            unknownCost = unknownCost || other.unknownCost
        }

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
        let dates = HistoryDates()
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let fileTotals = cachedTotals(at: url, kind: "claude", today: today, calendar: calendar) {
                var totals = Totals()
                let completed = forEachHistoryRow(at: url) { object in
                    guard
                          let timestamp = (object["timestamp"] as? String).flatMap(dates.parse),
                          timestamp >= start,
                          let row = parse(object)
                    else { return }
                    totals.add(tokens: row.0, cost: row.1, timestamp: timestamp, today: today)
                }
                return completed ? totals : nil
            }
            result.merge(fileTotals)
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

    private struct FileCacheKey: Hashable {
        let url: URL
        let kind: String
        let today: Date
        let calendar: Calendar
    }

    private struct FileCacheEntry: Sendable {
        let modified: Date
        let size: Int
        let totals: Totals
    }

    // Bounded aggregates only: never retain JSON, message bodies or file buffers.
    private static let fileCache = Mutex<[FileCacheKey: FileCacheEntry]>([:])

    private static func cachedTotals(
        at url: URL, kind: String, today: Date, calendar: Calendar, scan: () -> Totals?
    ) -> Totals {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let before = try? url.resourceValues(forKeys: keys),
              let modified = before.contentModificationDate, let size = before.fileSize else { return scan() ?? Totals() }
        let key = FileCacheKey(url: url, kind: kind, today: today, calendar: calendar)
        if let cached = fileCache.withLock({ $0[key] }), cached.modified == modified, cached.size == size {
            return cached.totals
        }
        guard let totals = scan() else { return Totals() }
        // Use a fresh URL to avoid Foundation's cached metadata. A changing file
        // is rescanned next time rather than committing a partial aggregate.
        let after = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
        if after?.contentModificationDate == modified, after?.fileSize == size {
            fileCache.withLock { entries in
                if entries.count >= 4096, entries[key] == nil, let oldest = entries.keys.first {
                    entries.removeValue(forKey: oldest)
                }
                entries[key] = FileCacheEntry(modified: modified, size: size, totals: totals)
            }
        }
        return totals
    }

    // Read one chunk at a time; retain only an unfinished row between reads.
    // A per-row pool releases Foundation JSON temporaries even on worker threads.
    // The consumed prefix is compacted only after 1MB accumulates: compacting on
    // every 64KB chunk copied the whole remainder each time (O(n^2) memmoves on
    // large session files, the hottest frame in production profiles).
    private static func forEachHistoryRow(at url: URL, consume: ([String: Any]) -> Void) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        var pending = Data()
        pending.reserveCapacity(256 * 1024)
        // Data indices are not guaranteed zero-based after removeFirst, so
        // track the cursor as a collection index, never as an integer offset.
        var start = pending.startIndex
        func parse(_ data: Data) {
            autoreleasepool {
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                consume(object)
            }
        }
        while true {
            let chunk: Data
            do { chunk = try file.read(upToCount: 64 * 1024) ?? Data() }
            catch { return false }
            if chunk.isEmpty { break }
            pending.append(chunk)
            var end = start
            var index = start
            while index < pending.endIndex {
                if pending[index] == 10 {
                    parse(Data(pending[end..<index]))
                    end = pending.index(after: index)
                }
                index = pending.index(after: index)
            }
            start = end
            if pending.distance(from: pending.startIndex, to: start) > 1_048_576 {
                pending.removeFirst(pending.distance(from: pending.startIndex, to: start))
                start = pending.startIndex
            }
        }
        if start < pending.endIndex { parse(Data(pending[start...])) }
        return true
    }

    private struct HistoryDates {
        private let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        private let seconds = Date.ISO8601FormatStyle()

        func timestamp(from value: Any?) -> Date? {
            if let value = value as? String { return parse(value) }
            if let value = TokenUsageScanner.number(value) {
                return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1_000 : value)
            }
            return nil
        }

        func parse(_ value: String) -> Date? {
            (try? fractional.parse(value)) ?? (try? seconds.parse(value))
        }
    }
}
