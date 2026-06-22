class Swamp < Formula
  desc "AI Native Automation CLI"
  homepage "https://github.com/swamp-club/swamp"
  version "20260621.232711.0-sha.61fdcac8"
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
      sha256 "ef118eb632aa87d80ca51a53b43085bd1be794d71dc3957965961e6f2ad33dc1"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-darwin-x86_64"
      sha256 "ea285989ab89fa58bf678d70ddaea0086a580c947c306f8905cf26c9a5830d18"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-aarch64"
      sha256 "0fdb3322d26de0a02ff24215f240188dffe5eb822394c5091af078e4b5e27e6d"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-x86_64"
      sha256 "53c33ba23f2f4831d34be4f69087b597c532548e4a99781a6d86960c5cd2fe79"
    end
  end

  def install
    bin.install Dir["swamp-*"].first => "swamp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swamp --version")
  end
end
