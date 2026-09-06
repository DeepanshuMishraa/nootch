import Foundation
import Testing
@testable import Nootch

// Regression cover for the 1.0.4 launch crash: `Bundle.module` resolved the
// resource bundle relative to the executable, missed it in a packaged .app, and
// called fatalError instead of reporting the miss.

// The crash itself. A packaged .app put the bundle somewhere Bundle.module did
// not look, and the miss was fatal. `locate` has to report the miss instead, so
// the app can degrade to SF Symbols.
@Test func locateReturnsNilWhenBundleIsAbsentInsteadOfTrapping() throws {
    let empty = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nootch-resource-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }

    #expect(ResourceBundle.locate(in: [empty]) == nil)
    #expect(ResourceBundle.locate(in: []) == nil)
}

@Test func locateFindsBundleAndSkipsDirectoriesWithoutIt() throws {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nootch-resource-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: missing) }

    let real = try #require(ResourceBundle.locate(in: ResourceBundle.searchPaths(
        main: .main, anchor: Bundle(for: ProviderLogoAnchor.self))))
    // A directory that does not hold the bundle must be skipped, not accepted.
    let found = try #require(ResourceBundle.locate(in: [missing, real.bundleURL.deletingLastPathComponent()]))
    #expect(found.bundleURL == real.bundleURL)
}

// The packaged .app keeps resources in Contents/Resources, so that has to be
// tried before the executable directory Bundle.module used.
@Test func searchPathsPrefersTheAppResourceDirectory() {
    let paths = ResourceBundle.searchPaths(main: .main, anchor: Bundle(for: ProviderLogoAnchor.self))
    let mainResources = try? #require(Bundle.main.resourceURL)
    #expect(paths.first == mainResources)
    #expect(!paths.isEmpty)
}

@Test func resourceBundleResolvesPackagedResources() {
    #expect(ResourceBundle.url(forResource: "claude", withExtension: "svg") != nil)
    #expect(ResourceBundle.url(forResource: "NootchIcon", withExtension: "png") != nil)
}

@Test func resourceBundleReturnsNilForMissingResource() {
    #expect(ResourceBundle.url(forResource: "definitely-not-a-resource", withExtension: "svg") == nil)
}

// Every provider that advertises a logo must actually ship one, otherwise the
// rail silently falls back to an SF Symbol. ProviderID.allCases is a curated
// display list that omits .openCodeGo, so cover that case explicitly.
@Test func everyProviderLogoResourceIsPresent() {
    for provider in ProviderID.allCases + [.openCodeGo] {
        guard let resource = provider.logoResource else { continue }
        #expect(
            ResourceBundle.url(forResource: resource, withExtension: nil) != nil,
            "missing logo resource \(resource) for \(provider.rawValue)")
    }
}

private final class ProviderLogoAnchor {}
