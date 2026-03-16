cask "smcfancontrol" do
  version "2.7.0"
  sha256 :no_check

  url "https://github.com/wolffcatskyy/smcFanControl/releases/download/v#{version}/smcFanControl-v#{version}.zip"
  name "smcFanControl Community Edition"
  desc "Fan control for Intel Macs. Set-and-forget fan speeds, sleep/wake fix, boot-time fan control."
  homepage "https://wolffcatskyy.dev/smcfancontrol"

  app "smcFanControl.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-rd", "com.apple.quarantine", "#{appdir}/smcFanControl.app"]
  end

  uninstall quit: "de.eidac.smcFanControl2"

  zap trash: [
    "~/Library/Preferences/de.eidac.smcFanControl2.plist",
    "~/Library/Application Support/smcFanControl",
  ]
end
