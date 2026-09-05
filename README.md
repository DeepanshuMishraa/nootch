# nootch

Keep an eye on your AI usage without leaving what you're working on. nootch shows usage limits and agent activity in a small, expandable overlay on your Mac.

Supports 10 integrations: Codex, Claude, OpenCode, ClinePass, Antigravity, Cursor, GitHub Copilot, Grok, xAI, and Z.ai. OpenCode includes Go credentials. Available usage data depends on your provider and account.

## Install

Requires an Apple Silicon Mac running macOS 15 Sequoia or later.

### Homebrew

```sh
brew tap deepanshumishraa/nootch https://github.com/DeepanshuMishraa/nootch
brew install --cask deepanshumishraa/nootch/nootch
open -a nootch
```

The cask automatically removes quarantine from `nootch.app`. The app isn't notarized, so this bypasses Gatekeeper's downloaded-app check for nootch only. It does not disable Gatekeeper system-wide. Install only if you trust this project.

### Download

Grab the DMG from [Releases](https://github.com/DeepanshuMishraa/nootch/releases/latest), open it, and drag `nootch.app` into Applications.

If macOS blocks it, remove quarantine from this app and open it:

```sh
xattr -dr com.apple.quarantine /Applications/nootch.app
open -a nootch
```

Sign in to the providers you use through their apps or CLIs first. nootch reads supported local credentials and refreshes usage every 30 seconds. API-key providers need their credentials configured separately.

## Run from source

With Xcode Command Line Tools and Swift 6 installed:

```sh
git clone https://github.com/DeepanshuMishraa/nootch.git
cd nootch
swift run nootch
```

Run tests with `swift test`. Build the app and DMG with `packaging/build-app.sh`.
