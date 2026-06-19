class Swamp < Formula
  desc "AI Native Automation CLI"
  homepage "https://github.com/swamp-club/swamp"
  version "20260619.091244.0-sha.43c65b72"
  license "AGPL-3.0-only"

  livecheck do
    url :stable
    regex(/^v?(.+)$/i)
    strategy :github_latest
  end

  # Upstream publishes the binary for each platform as a bare (un-archived)
  # GitHub release asset; sha256 values come from the release's checksums.txt.
  on_macos do
    on_arm do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-darwin-aarch64"
      sha256 "dbe041ce5fbe6387da795eb3cf7bf5e5ff5228038f1cef3cb0a62418e3a2dce1"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-darwin-x86_64"
      sha256 "71d4cfe22f4ce216b434bbec7cf061524063187b5c839a44c7ab3b014fa40c8e"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-aarch64"
      sha256 "eb29b7fa500ce8aed8126c9a434d52d25107512f781aba96e5a837ed719760e9"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-x86_64"
      sha256 "f912cbd0a9db86280ad856589b177e565e3c380fb6d6c89a3537fceb242d936c"
    end
  end

  def install
    bin.install Dir["swamp-*"].first => "swamp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swamp --version")
  end
end
