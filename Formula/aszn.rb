class Aszn < Formula
  desc "Alias Zone: per-directory zsh aliases that load on cd and unload on exit"
  homepage "https://github.com/coder11v/aszn"
  url "https://github.com/coder11v/aszn/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_ME_RUN_scripts/release.zsh"
  license "MIT"
  head "https://github.com/coder11v/aszn.git", branch: "main"

  uses_from_macos "zsh"

  def install
    bin.install "bin/aszn"
    (share/"aszn").install "aszn.zsh", "aszn.plugin.zsh"
  end

  def caveats
    <<~EOS
      To enable aszn in your shell, run:
        aszn install
      then restart your terminal (or run: exec zsh).

      Before `brew uninstall aszn`, run `aszn uninstall` to clean up ~/.zshrc.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/aszn version")
    ENV["ZDOTDIR"] = testpath
    system bin/"aszn", "install"
    assert_match "aszn.zsh", (testpath/".zshrc").read
  end
end
