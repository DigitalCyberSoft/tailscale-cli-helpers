class TailscaleCliHelpers < Formula
  desc "Command-line helpers for Tailscale SSH operations"
  homepage "https://github.com/DigitalCyberSoft/tailscale-cli-helpers"
  url "https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/v0.3.6.tar.gz"
  sha256 "9ae272fb6b856790cb2418448d3e48117b0a210a23d6a1d0f064cd505f50cb56"
  license "MIT"

  depends_on "jq"
  depends_on "tailscale"

  # Optional dependency - will be used if available
  uses_from_macos "rsync"

  def install
    # Executables resolve shared libraries at ../lib relative to themselves,
    # so installing to prefix/bin and prefix/lib needs no path rewriting
    bin.install Dir["bin/*"]
    (prefix/"lib").install "lib/common.sh", "lib/tailscale-resolver.sh"

    man1.install Dir["man/man1/*.1"]

    bash_completion.install "bash-completion/tailscale-completion.sh" => "tailscale-cli-helpers"

    doc.install "README.md"
  end

  def caveats
    <<~EOS
      Requirements:
        - Tailscale must be installed, running, and logged in

      tmussh (parallel SSH) additionally needs mussh:
        brew install mussh
    EOS
  end

  test do
    system "#{bin}/ts", "--help"
    system "#{bin}/tssh", "--help"
    assert_match version.to_s, shell_output("#{bin}/ts --version")
  end
end
