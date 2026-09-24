# Homebrew cask for Claudy.
#
# Publishing: copy this file into the `Endikk/homebrew-claudy` tap (Casks/ directory),
# then update `version` AND `sha256` on every release:
#   shasum -a 256 dist/Claudy-<version>.zip
#
# SECURITY: `sha256` must always be pinned (never `:no_check`). It is the only integrity
# check in the chain: the postflight below removes the quarantine flag, so it must only
# ever apply to an artefact whose digest Homebrew has verified.
#
# User install:
#   brew install --cask Endikk/claudy/claudy
cask "claudy" do
  version "1.5.5"
  sha256 "ee59065a1d9444facb0f2bf15496d34fc2b5e4b81080d1cd4f315b41aba37885"

  url "https://github.com/Endikk/Claudy/releases/download/v#{version}/Claudy-#{version}.zip"
  name "Claudy"
  desc "Desktop widget showing Claude quotas and usage in real time"
  homepage "https://github.com/Endikk/Claudy"

  depends_on macos: :ventura

  app "Claudy.app"

  # The app is not notarised (free distribution, no Apple Developer account):
  # without removing the quarantine flag, Gatekeeper would refuse to launch it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Claudy.app"]
  end

  uninstall quit: "com.claudy.Claudy"

  zap trash: [
    "~/Library/Application Support/Claudy",
    "~/Library/Preferences/com.claudy.Claudy.plist",
  ]

  caveats <<~EOS
    Claudy is not notarised by Apple (free project, no paid developer account).
    The cask removes the quarantine flag automatically. The code is open source:
    https://github.com/Endikk/Claudy, build it yourself if you prefer.
  EOS
end
