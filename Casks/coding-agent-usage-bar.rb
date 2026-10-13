cask "coding-agent-usage-bar" do
  # 個人 tap 用なので、リリースごとに sha256 を書き換えずに済む形にしている
  version :latest
  sha256 :no_check

  url "https://github.com/saba383810/coding-agent-usage-bar/releases/latest/download/CodingAgentUsageBar.zip"
  name "Coding Agent Usage Bar"
  desc "Shows Claude Code and Codex usage in the macOS menu bar"
  homepage "https://github.com/saba383810/coding-agent-usage-bar"

  # 未署名 (ad-hoc 署名) のため、quarantine 属性が付いたままだと Gatekeeper に止められる。
  # 今の Homebrew には --no-quarantine が無いので、インストール後にこちらで外す。
  app "CodingAgentUsageBar.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/CodingAgentUsageBar.app"]
  end

  uninstall quit: "io.saba383810.CodingAgentUsageBar"

  zap trash: [
    "~/Library/Preferences/io.saba383810.CodingAgentUsageBar.plist",
  ]
end
