cask "stasis" do
  version "0.0.5"
  sha256 "eef91ca48b90a9c2789750e085dbdfa53ab0c7088ef534ada9e76fdc67656138"

  url "https://github.com/DinanathDash/Stasis/releases/download/v#{version}/Stasis.dmg"
  name "Stasis"
  desc "Battery management tool (Dinanath's Fork)"
  homepage "https://github.com/DinanathDash/Stasis"

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