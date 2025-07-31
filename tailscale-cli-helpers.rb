class TailscaleCliHelpers < Formula
  desc "Command-line helpers for Tailscale SSH operations"
  homepage "https://github.com/DigitalCyberSoft/tailscale-cli-helpers"
  url "https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "375cd62c23920f5945ba1ea8c1540b22bc0cd727494295f5f5415535de7c97e5"
  license "MIT"

  depends_on "jq"
  depends_on "tailscale"
  
  # Optional dependency - will be used if available
  uses_from_macos "rsync"

  def install
    # Install executables
    bin.install Dir["bin/*"]
    
    # Install shared libraries
    libexec.install "lib/tailscale-resolver.sh"
    libexec.install "lib/common.sh"
    
    # Create wrapper scripts that source the libraries
    Dir["#{bin}/*"].each do |script|
      script_name = File.basename(script)
      next if script_name == "tmussh" && !Formula["mussh"].any_version_installed?
      
      inreplace script do |s|
        # Update library paths to point to libexec
        s.gsub! '$(dirname "$(realpath "$0")")/../lib/common.sh', "#{libexec}/common.sh"
        s.gsub! '$(dirname "$(realpath "$0")")/../lib/tailscale-resolver.sh', "#{libexec}/tailscale-resolver.sh"
      end
    end
    
    # Install man pages
    man1.install Dir["man/man1/*.1"]
    
    # Install setup script
    libexec.install "setup.sh"
    
    # Install documentation
    doc.install "README.md"
    doc.install "CLAUDE.md" if File.exist?("CLAUDE.md")
    
    # Install bash completions
    bash_completion.install_symlink bin/"ts" => "tailscale-cli-helpers"
    bash_completion.install_symlink bin/"tssh"
    bash_completion.install_symlink bin/"tscp"
    bash_completion.install_symlink bin/"tsftp" if File.exist?("#{bin}/tsftp")
    bash_completion.install_symlink bin/"trsync" if File.exist?("#{bin}/trsync")
    bash_completion.install_symlink bin/"tssh_copy_id"
  end

  def post_install
    # Check if mussh is available and suggest installing tmussh
    if Formula["mussh"].any_version_installed? && !File.exist?("#{bin}/tmussh")
      opoo "mussh is installed. Consider reinstalling tailscale-cli-helpers to enable tmussh command."
    end
  end

  def caveats
    mussh_note = if Formula["mussh"].any_version_installed?
      "\n      tmussh is available for parallel SSH execution"
    else
      "\n      Install mussh to enable tmussh for parallel SSH: brew install mussh"
    end
    
    <<~EOS
      Tailscale CLI helpers have been installed.
      
      Available commands:
        ts [hostname]                    # Quick SSH to Tailscale nodes
        tssh hostname                    # SSH to Tailscale host
        tscp file.txt host:/path/        # Copy files (if scp available)
        tsftp hostname                   # SFTP to Tailscale host (if sftp available)
        trsync -av dir/ host:/path/      # Sync directories (if rsync available)
        tssh_copy_id hostname            # Copy SSH keys to Tailscale host#{mussh_note}
        
      Tab completion is available for all commands.
        
      Requirements:
        - Tailscale must be installed and running
        - You must be logged into your Tailscale network
    EOS
  end

  test do
    # Test that commands are available and show help
    system "#{bin}/ts", "--help"
    system "#{bin}/tssh", "--help"
    
    # Test version flag
    assert_match version.to_s, shell_output("#{bin}/ts --version")
  end
end