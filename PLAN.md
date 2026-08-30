# CodexBar-Inspired macOS Usage Notch

## Context
- This repository is currently empty (`git ls-files` returned no tracked files); implementation will establish the initial SwiftUI/AppKit macOS app structure.
- The target is a menu-bar/system utility with a side-notch-style usage display inspired by the supplied image and `steipete/CodexBar`.
- The app should discover locally installed AI providers, obtain provider-specific usage/quota data, normalize it, and present compact status plus an expanded detail surface.
- Confirmed scope: macOS 15 Sequoia; right-edge vertical notch/rail (not a menu-bar app); launch at login; provider coverage should follow CodexBar's major-provider strategy; use both local detection/sources and provider APIs where available.

## Approach
- Build a native SwiftUI macOS app with an AppKit `NSPanel` overlay for the right-edge notch/rail presentation, rather than a menu-bar or normal app window. Keep a small settings/preferences window for configuration and diagnostics.
- Separate provider discovery, provider adapters, usage normalization, refresh/caching, and UI state so provider-specific APIs do not leak into views.
- Use CodexBar's descriptor-driven provider registry as the architectural model: each provider declares metadata, availability, ordered fetch strategies, credential/auth handling, and presentation capabilities; the app runs only strategies whose local prerequisites are detected and falls back in order.
- First reproduce the reference architecture and supported provider behavior from the upstream repository; then implement a narrow tracer-bullet provider and overlay before broadening coverage.
- Treat credentials and local provider state as sensitive: autodetection should inspect known local installation/configuration locations without copying or exposing secrets.

## Files to modify
- TBD after repository/upstream inspection; expected initial areas:
  - Swift package/Xcode project files
  - App entry point and lifecycle/menu-bar integration
  - `AppKit` notch/overlay panel and geometry
  - SwiftUI usage/status views
  - Provider registry, discovery, adapters, normalized usage models
  - Tests and documentation

## Reuse
- Repository is empty; no existing implementation to reuse.
- Local macOS guidance: `macos-notch-ui` recommends a transparent, non-activating `NSPanel`, top-level window positioning, custom notch shape, multi-display handling, and reduced-motion/fallback behavior.
- Local macOS guidance: `macos-patterns` covers status items, window levels, Spaces/fullscreen behavior, AppKit coordinate systems, and launch-at-login patterns.

## Steps
- [x] Inspect the upstream CodexBar repository structure, provider adapters, discovery logic, usage calculations, caching/refresh behavior, and UI/window lifecycle.
- [x] Confirm product scope and provider/authentication boundaries with the user.
- [x] Create the native macOS project skeleton and app lifecycle.
- [x] Implement typed provider discovery and a normalized usage model with provider-specific adapter boundaries.
- [x] Implement a bounded refresh loop and explicit unavailable/error states.
- [x] Implement the right-edge panel, compact provider indicators, expanded usage detail, and spring animation behavior.
- [x] Add initial tests for parsing and percentage normalization.
- [x] Add real OAuth/API/local-auth usage fetchers for Codex, Claude, Antigravity, Cursor, and Copilot, including reset-time mapping and last-success retention.
- [x] Run package tests and whitespace validation.
- [ ] Manually verify authenticated responses and overlay geometry across notch and non-notch/multi-display setups.

## Upstream findings
- CodexBar is split into `Sources/CodexBarCore` (fetching/parsing/provider contracts) and `Sources/CodexBar` (state/UI), with separate CLI/widget/helper targets. Its data flow is refresh → provider strategies → `UsageStore` → menu/icon/widget projections.
- Providers are descriptor-driven and use ordered strategies such as OAuth, CLI RPC/PTY, API token, browser cookies/WebView, and local probes. Availability checks are cached and settings/config changes invalidate the cache. The intended extension boundary is one provider folder plus descriptor/strategies/tests/docs, not central UI branching.
- The normalized quota model is `RateWindow`: `usedPercent`, optional `windowMinutes`, optional absolute `resetsAt`, optional reset text, and optional metadata for synthetic/unknown lanes. A provider can expose primary, secondary, tertiary, and named extra windows. Identity and credentials remain provider-scoped.
- Percentages are provider-reported when available. For CLI output that reports remaining percentage, CodexBar computes `used = clamp(100 - percentLeft, 0...100)`. For API responses that report used percentage, it stores that value and derives `remaining = max(0, 100 - used)`. Reset epoch seconds are converted to `Date`; absent/invalid denominators are not turned into fake percentages.
- Codex's automatic strategy order is PAT/local auth, OAuth, then CLI; Claude uses configured Admin API/OAuth/CLI/web paths. The implementation distinguishes subscription quota windows from API spend and local token-cost estimates rather than merging unlike meters.
- Refresh is centralized in `UsageStore`, coalesces concurrent refreshes, preserves the last successful snapshot when a replacement fails, surfaces stale/error state, and supports manual plus adaptive timed refresh. Adaptive cadence considers interaction/activity/power/thermal state; our first version can use a simpler bounded interval.
- The supplied image implies a separate right-edge overlay: a narrow vertical provider rail with circular usage gauges expands into a horizontal/left-facing detail card. This is distinct from CodexBar's current menu-bar UI and should be implemented as a custom non-activating AppKit panel.

## Verification
- Compare provider parsing and percentage/reset outputs against upstream fixtures or observed behavior.
- Unit-test provider detection and usage calculations, including missing/expired/partial data.
- Build with `xcodebuild` and run the app manually: launch, provider discovery, refresh, click/hover expansion, reset countdown, errors, quit, and relaunch.
- Verify overlay placement across notch and non-notch displays, Spaces/fullscreen, light/dark appearance, Reduce Motion, and click-through behavior.
- Every provider adapter is implemented directly in Usage Notch with no CodexBar package/runtime dependency. CodexBar was used only as a behavioral reference. Missing or invalid credentials produce explicit errors, and no usage values are fabricated.
