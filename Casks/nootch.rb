cask "nootch" do
  version "1.0.4"
  sha256 "025dc18e73d0ad584953d8f1ff68b7c475eb6b20f211ae1f5f636f4acb09257d"

  url "https://github.com/DeepanshuMishraa/nootch/releases/download/v#{version}/nootch-#{version}.dmg"
  name "nootch"
  desc "AI provider usage and agent activity overlay"
  homepage "https://github.com/DeepanshuMishraa/nootch"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "nootch.app"

  postflight_steps do
    # This ad-hoc-signed app is not notarized. Only remove its quarantine flag.
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/nootch.app"]
  end

  caveats <<~EOS
    nootch is not notarized. This cask removes quarantine from nootch.app,
    bypassing Gatekeeper's downloaded-app check for this app only.
    Gatekeeper remains enabled for other apps. Install only if you trust nootch.
  EOS
end
