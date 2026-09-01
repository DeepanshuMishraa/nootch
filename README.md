# Agent Notch

A native SwiftUI/AppKit macOS utility that shows installed AI providers in a right-edge expandable usage rail.

## Current state

The first slice includes:

- A macOS 15 Swift Package executable.
- Typed provider adapters for Codex, Claude, OpenCode, OpenCode Go, ClinePass, Antigravity, Cursor, and Copilot.
- Credential-aware detection so only authenticated, usable providers appear.
- A normalized `UsageWindow` model that clamps percentages and converts remaining percentages.
- A floating, all-Spaces right-edge `NSPanel` with compact rings and an expanded detail card.
- Automatic background refresh every 30 seconds.
- Launch-at-login registration for bundled `.app` builds.

Agent Notch implements each provider integration directly. It has no CodexBar package or runtime dependency. The quota sources are:

- Codex: local `~/.codex/auth.json` OAuth/PAT credentials and OpenAI's usage endpoint.
- Claude: Claude Code Keychain OAuth credentials and Anthropic's OAuth usage endpoint.
- OpenCode Go: local OpenCode Go credentials and its usage API.
- OpenCode: local CLI installation detection. Authenticated web usage requires an OpenCode session cookie.
- ClinePass: ClinePass API key and its usage-limits API.
- Antigravity: Antigravity OAuth credentials and Google's Cloud Code quota API.
- Cursor: Cursor.app auth with cached/browser-session fallback and Cursor's usage API.
- Copilot: GitHub OAuth from `gh auth token` and GitHub's Copilot internal usage API.

The UI keeps the last successful snapshot during later refresh failures and never invents usage values.

## Run

```sh
swift run AgentNotch
```

## Test

```sh
swift test
```
