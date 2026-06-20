class Swamp < Formula
  desc "AI Native Automation CLI"
  homepage "https://github.com/swamp-club/swamp"
  version "20260620.010743.0-sha.f0896067"
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
      sha256 "f3cdaef68228bc4bc90537871356c568c68e7fc2fe324706d3b865d0662d6f9e"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-darwin-x86_64"
      sha256 "6a2dac86f1b6a0c3388a9a93861aa08e0735d646280989a676a3830942dd575a"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-aarch64"
      sha256 "d72d4280528d6440f6cdd505b2ac95f8c5b856b3d19c85fd8bcb532606e07247"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-x86_64"
      sha256 "68264dcb9dca8191fb7585e85f1e14cd30b9ff317d714fd3f655780716951eb8"
    end
  end

  def install
    bin.install Dir["swamp-*"].first => "swamp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swamp --version")
  end
end
