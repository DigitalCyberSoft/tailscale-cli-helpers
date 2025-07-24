class TailscaleCliHelpers < Formula
  desc "Bash/Zsh functions for easy SSH access to Tailscale nodes"
  homepage "https://github.com/DigitalCyberSoft/tailscale-cli-helpers"
  url "https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "03d2b487013b33f4b690455d8435fc6545b05d22736a3b2370d1b96277b56f3a"
  license "MIT"

  depends_on "jq"
  depends_on "tailscale"

  def install
    # Install scripts to libexec
    libexec.install "tailscale-ssh-helper.sh"
    libexec.install "tailscale-functions.sh"
    libexec.install "tailscale-completion.sh"
    libexec.install "tailscale-mussh.sh"
    libexec.install "tailscale-ts-dispatcher.sh"
    
    # Install setup script
    libexec.install "setup.sh"
    
    # Install documentation
    doc.install "README.md"
    doc.install "CLAUDE.md"
  end

  def post_install
    # Add to shell profile
    shell_profile = if ENV["SHELL"].include?("zsh")
                      "#{Dir.home}/.zshrc"
                    else
                      "#{Dir.home}/.bash_profile"
                    end
    
    source_line = "source \"#{libexec}/tailscale-ssh-helper.sh\""
    
    unless File.read(shell_profile).include?(source_line)
      File.open(shell_profile, "a") do |f|
        f.puts ""
        f.puts "# Tailscale CLI helpers"
        f.puts source_line
      end
    end
  end

  def caveats
    <<~EOS
      Tailscale CLI helpers have been installed.
      
      To use the 'ts' command and ssh-copy-id enhancements:
      1. Restart your terminal, or
      2. Run: source ~/.zshrc (or ~/.bash_profile)
      
      Usage:
        tssh hostname                    # SSH to Tailscale host
        ts hostname                      # SSH via dispatcher (same as tssh)
        tscp file.txt host:/path/        # Copy files
        trsync -av dir/ host:/path/      # Sync directories
        tmussh -h host1 host2 -c "cmd"   # Parallel SSH (requires mussh)
        ts <TAB>                         # Tab completion
        
      Requirements:
        - Tailscale must be installed and running
        - You must be logged into your Tailscale network
    EOS
  end

  test do
    # Test that the main script can be sourced and commands are available
    system "bash", "-c", "source #{libexec}/tailscale-ssh-helper.sh && type tssh && type ts"
  end
end