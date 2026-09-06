import Foundation
import Testing
@testable import Nootch

// Regression cover for the 1.0.4 launch crash: `Bundle.module` resolved the
// resource bundle relative to the executable, missed it in a packaged .app, and
// trapped instead of returning nil.
@Test func resourceBundleResolvesPackagedResources() {
    #expect(ResourceBundle.url(forResource: "claude", withExtension: "svg") != nil)
    #expect(ResourceBundle.url(forResource: "NootchIcon", withExtension: "png") != nil)
}

@Test func resourceBundleReturnsNilForMissingResourceInsteadOfTrapping() {
    #expect(ResourceBundle.url(forResource: "definitely-not-a-resource", withExtension: "svg") == nil)
}

// Every provider that advertises a logo must actually ship one, otherwise the
// rail silently falls back to an SF Symbol.
@Test func everyProviderLogoResourceIsPresent() {
    for provider in ProviderID.allCases {
        guard let resource = provider.logoResource else { continue }
        #expect(
            ResourceBundle.url(forResource: resource, withExtension: nil) != nil,
            "missing logo resource \(resource) for \(provider.rawValue)")
    }
}
