# Agent activity indicators

## Context
- nootch already renders provider usage rings, but it does not show whether a local coding agent is working, waiting for user action, finished, or idle.
- The requested behavior is to inspect Herdr's real status detection, then apply the same state model to this app without requiring Herdr to be installed.
- Usage color should continue to reflect quota pressure: green for highest remaining usage, yellow for lower usage, and red for very low usage. While an agent is working, the ring should spin without replacing the quota color. Needs-action gets a separate visual treatment. Finished keeps the current/default appearance, so there is no new persistent finished badge.

## Approach
- First map Herdr's detection pipeline and status semantics from its source, then map those states onto nootch's existing provider model.
- Add a typed agent activity state and a detection/refresh path that reports `working`, `blocked`/needs action, `done`, `idle`, or `unknown` without treating quota refresh state as agent activity.
- Use direct local detection, not Herdr APIs: identify known agent processes, observe their local activity/session evidence, and use agent-specific rules for approval prompts where evidence is available. Keep the detector best-effort and explicit about unknown states.
- Update the provider ring UI so working rings animate/spin, action-needed rings have a clear static attention treatment, done and idle rings retain today's appearance, and quota color remains independent from activity state.
- Preserve existing quota thresholds and colors, reduce-motion behavior, last-success usage caching, and explicit unavailable/error handling.

## Files to modify
- `Sources/Nootch/Domain.swift`: typed activity state, agent identity, and provider-level activity projection.
- `Sources/Nootch/AgentActivityDetector.swift`: macOS-local process/activity polling and conservative agent-specific evidence rules, independent of Herdr.
- `Sources/Nootch/UsageStore.swift`: merge activity snapshots with quota refreshes and expose a separate activity refresh cadence.
- `Sources/Nootch/NootchApp.swift`: start and stop the activity monitor with the app lifecycle.
- `Sources/Nootch/NotchPanel.swift`: spin only working rings, add a distinct needs-action treatment, and leave done/idle rendering unchanged.
- `Tests/NootchTests/NootchTests.swift` or focused new test files: detector mapping, state transitions, provider mapping, and presentation decisions.

## Reuse
- Existing `UsageStore` owns refresh state and cached provider snapshots in `Sources/Nootch/UsageStore.swift`; quota fetching and activity polling should remain separate so a slow API call cannot make an agent look busy.
- Existing `ProviderStatus` in `Sources/Nootch/Domain.swift` should carry the typed activity projection rather than view-only string flags.
- Existing `UsageWindow.tierColor` and `gradient` already implement the green/yellow/red remaining-usage thresholds. Do not recolor working rings with a generic busy color.
- Existing `ProviderRailItem` in `Sources/Nootch/NotchPanel.swift` owns the compact ring and is the only place that needs motion/attention presentation logic.
- Herdr's useful behavior is the state model and conservative arbitration: process identity first, agent-specific evidence second, explicit unknown fallback, and publish changes only. Its implementation is reference material, not a runtime dependency.

## Steps
- [x] Locate Herdr source and document how terminal output/session metadata becomes agent states.
- [x] Inspect current nootch models, store, panel, ring views, and tests.
- [x] Choose and implement a direct local detector that does not require Herdr, with process/session evidence and conservative unknown fallbacks.
- [x] Add typed activity state, state transitions, and attention/seen semantics.
- [x] Add spinning/attention/idle UI states while preserving quota colors.
- [x] Add deterministic tests for detection mapping, transitions, and color-plus-motion behavior.
- [x] Run Swift tests and whitespace validation.
- [ ] Manually verify live agent transitions and visual treatment in the running app.

## Verification
- Unit-test the local detector's process/activity and agent-rule mapping with working, blocked, done, idle, and unknown samples.
- Confirm quota color stays green/yellow/red independently of activity state.
- Manually start supported agents, wait for work, an approval request, completion, and idle prompt, and verify the rail updates and stops spinning at each transition. This remains pending because the app was not launched during validation.
- Verify Reduce Motion disables or softens the spin and that cached usage remains visible during detector/API failures.
