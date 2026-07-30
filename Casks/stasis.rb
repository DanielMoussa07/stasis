cask "stasis" do
  version "0.15.1"
  sha256 "4e43a57114cc479c19305b13fe4c075d79c543aabf2c0653505215b952c1882f"

  url "https://github.com/DinanathDash/Stasis/releases/download/v#{version}/Stasis.dmg"
  name "Stasis"
  desc "Battery management tool (Dinanath's Fork)"
  homepage "https://github.com/DinanathDash/Stasis"

  auto_updates true

  app "Stasis.app"

  uninstall quit:      "com.dinanathdash.stasis",
            launchctl: [
              "com.dinanathdash.stasis.helper",
              "com.dinanathdash.stasis.charging-helper"
            ],
            delete:    [
              "/Library/PrivilegedHelperTools/com.dinanathdash.stasis.helper",
              "/Library/PrivilegedHelperTools/com.dinanathdash.stasis.charging-helper"
            ]
end