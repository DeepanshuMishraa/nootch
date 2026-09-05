import Foundation
import Testing
@testable import Nootch

@Test func renamePreservesPreferencesAndCachesWithoutOverwritingNewValues() throws {
    let suite = "nootch.rename-tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "UsageNotch.showInDock")
    defaults.set("blue", forKey: "UsageNotch.themeColor")
    defaults.set("red", forKey: AppSettings.themeColorKey)
    defaults.set(Data([1, 2, 3]), forKey: "UsageNotch.providerStatusCache.v1")

    AppSettings.migrateLegacyPreferences(defaults: defaults, legacyDomainNames: [])

    #expect(defaults.object(forKey: AppSettings.showInDockKey) != nil)
    #expect(defaults.bool(forKey: AppSettings.showInDockKey) == false)
    #expect(defaults.string(forKey: AppSettings.themeColorKey) == "red")
    #expect(defaults.data(forKey: "nootch.providerStatusCache.v1") == Data([1, 2, 3]))

    defaults.removeObject(forKey: "nootch.providerStatusCache.v1")
    AppSettings.migrateLegacyPreferences(defaults: defaults, legacyDomainNames: [])
    #expect(defaults.data(forKey: "nootch.providerStatusCache.v1") == nil)
}

@Test func renameImportsPreferencesFromPreviousBundleDomain() throws {
    let suite = "nootch.rename-tests.\(UUID().uuidString)"
    let legacySuite = suite + ".legacy"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
        defaults.removePersistentDomain(forName: suite)
        defaults.removePersistentDomain(forName: legacySuite)
    }
    defaults.setPersistentDomain(["UsageNotch.animationDuration": 0.5], forName: legacySuite)

    AppSettings.migrateLegacyPreferences(defaults: defaults, legacyDomainNames: [legacySuite])

    #expect(defaults.double(forKey: AppSettings.animationDurationKey) == 0.5)
}
