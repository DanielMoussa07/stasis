cask "stasis" do
  version "0.8.0"
  sha256 "4fb021423e6689bf09dd76a599e59b3f0f5725eda7f44bb43557bdb7171f134d"

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