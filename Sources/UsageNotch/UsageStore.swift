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

    init(adapters: [any ProviderAdapter] = ProviderDiscovery.defaultAdapters) {
        self.adapters = adapters
        self.statuses = Self.loadCachedStatuses()
        self.lastRefresh = self.statuses.compactMap(\.updatedAt).max()
    }

    var detectedStatuses: [ProviderStatus] { statuses.filter(\.detected) }

    func refresh() {
        guard !isRefreshing else { return }
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
                guard fresh.error != nil,
                      fresh.primary == nil,
                      fresh.secondary == nil,
                      let previous = previousByProvider[fresh.provider],
                      previous.primary != nil || previous.secondary != nil
                else { return fresh }
                return ProviderStatus(
                    provider: fresh.provider,
                    detected: fresh.detected,
                    source: fresh.source ?? previous.source,
                    primary: previous.primary,
                    secondary: previous.secondary,
                    error: fresh.error,
                    updatedAt: previous.updatedAt,
                    costUsage: previous.costUsage)
            }
            Self.saveCachedStatuses(self.statuses)
            self.lastRefresh = Date()
            self.isRefreshing = false
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
