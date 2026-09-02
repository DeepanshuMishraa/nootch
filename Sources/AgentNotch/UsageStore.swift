import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private static let cacheKey = "UsageNotch.providerStatusCache.v1"

    private(set) var statuses: [ProviderStatus] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private let adapters: [any ProviderAdapter]
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var activityTask: Task<Void, Never>?
    private let activityDetector: AgentActivityDetector

    init(
        adapters: [any ProviderAdapter] = ProviderDiscovery.defaultAdapters,
        activityDetector: AgentActivityDetector = AgentActivityDetector())
    {
        self.activityDetector = activityDetector
        self.adapters = adapters
        self.statuses = Self.loadCachedStatuses()
        self.lastRefresh = self.statuses.compactMap(\.updatedAt).max()
    }

    var detectedStatuses: [ProviderStatus] {
        // Installed providers remain visible even when they do not expose a
        // quota endpoint (for example, the OpenCode CLI).
        statuses.filter {
            $0.detected && AppSettings.isProviderEnabled($0.provider)
        }
    }

    func refreshActivity() {
        guard activityTask == nil else { return }
        let detector = activityDetector
        activityTask = Task { @MainActor in
            let snapshot = await Task.detached(priority: .utility) { detector.snapshot() }.value
            guard !Task.isCancelled else { return }
            guard snapshot.isReliable else {
                self.activityTask = nil
                return
            }
            self.statuses = self.statuses.map { status in
                status.withActivity(snapshot.activityByProvider[status.provider] ?? .done)
            }
            self.activityTask = nil
        }
    }

    func refresh() {
        refreshActivity()
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        refreshRequested = false
        isRefreshing = true
        refreshTask = Task { [adapters] in
            let fetched = await Task.detached(priority: .utility) {
                await withTaskGroup(of: ProviderStatus.self, returning: [ProviderStatus].self) { group in
                    for adapter in adapters {
                        group.addTask { await adapter.fetch() }
                    }
                    var values: [ProviderStatus] = []
                    for await value in group { values.append(value) }
                    return values.sorted { $0.provider.name < $1.provider.name }
                }
            }.value
            guard !Task.isCancelled else { return }
            let previousByProvider = Dictionary(uniqueKeysWithValues: self.statuses.map { ($0.provider, $0) })
            self.statuses = fetched.map { fresh in
                let status: ProviderStatus
                if fresh.error != nil,
                   fresh.primary == nil,
                   fresh.secondary == nil,
                   let previous = previousByProvider[fresh.provider],
                   previous.primary != nil || previous.secondary != nil
                {
                    status = ProviderStatus(
                        provider: fresh.provider,
                        detected: fresh.detected,
                        source: fresh.source ?? previous.source,
                        primary: previous.primary,
                        secondary: previous.secondary,
                        error: fresh.error,
                        updatedAt: previous.updatedAt,
                        costUsage: previous.costUsage,
                        activity: previous.activity)
                } else {
                    status = fresh
                }
                return status.withActivity(previousByProvider[fresh.provider]?.activity ?? status.activity)
            }
            Self.saveCachedStatuses(self.statuses)
            self.lastRefresh = Date()
            self.isRefreshing = false
            if self.refreshRequested {
                self.refresh()
            }
        }
    }

    private static func loadCachedStatuses() -> [ProviderStatus] {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([ProviderStatus].self, from: data)
        else { return [] }
        return cached.sorted { $0.provider.name < $1.provider.name }
    }

    private static func saveCachedStatuses(_ statuses: [ProviderStatus]) {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}
