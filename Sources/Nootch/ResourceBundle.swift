import Foundation
import os

// SwiftPM's generated `Bundle.module` resolves the resource bundle relative to
// the executable. For an `.app` that is the bundle root, not
// `Contents/Resources` where a packaged app keeps its resources, so the lookup
// misses and the generated accessor calls `assertionFailure` — the app dies
// during launch instead of degrading. Moving the bundle to the app root to
// satisfy `Bundle.module` would leave unsealed contents there and invalidate
// the code signature, so search the plausible locations here instead and let
// callers fall back when nothing is found.
enum ResourceBundle {
    private static let bundleName = "nootch_Nootch.bundle"

    // Anchors `Bundle(for:)` to whatever binary this module ended up in, which
    // is the one case Bundle.main cannot describe: under `swift test` the main
    // bundle is xctest, not the code under test.
    private final class ModuleAnchor {}

    static let current: Bundle = {
        var searched: [URL] = []
        // Packaged .app: nootch.app/Contents/Resources/nootch_Nootch.bundle
        if let resourceURL = Bundle.main.resourceURL { searched.append(resourceURL) }
        // Bare SwiftPM build: alongside the executable, where Bundle.module looks.
        if let executableDirectory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            searched.append(executableDirectory)
        }
        searched.append(Bundle.main.bundleURL)
        // Any host process that is not the app itself, notably `swift test`,
        // where the bundle is a sibling of the .xctest bundle rather than
        // inside it.
        let anchor = Bundle(for: ModuleAnchor.self)
        if let anchorResources = anchor.resourceURL { searched.append(anchorResources) }
        searched.append(anchor.bundleURL.deletingLastPathComponent())

        for directory in searched {
            let candidate = directory.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        // Resources copied loose into the main bundle. Reaching here usually
        // means a broken install rather than a real layout: logos fall back to
        // SF Symbols and the dock icon disappears, which under LSUIElement is
        // otherwise invisible. Leave a trace so it can be diagnosed.
        Logger(subsystem: "com.deepanshumishraa.nootch", category: "resources")
            .error("\(bundleName, privacy: .public) not found in \(searched.map(\.path), privacy: .public); falling back to the main bundle")
        return Bundle.main
    }()

    static func url(forResource resource: String, withExtension extension: String?) -> URL? {
        current.url(forResource: resource, withExtension: `extension`)
    }
}
