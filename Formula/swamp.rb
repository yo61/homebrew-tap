class Swamp < Formula
  desc "AI Native Automation CLI"
  homepage "https://github.com/swamp-club/swamp"
  version "20260620.200156.0-sha.d9abe1a2"
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
      sha256 "c8fc01c2b4d1574d899d1b964f1f098eb4ed1f0b84fa4c89b4705a8351a0fe57"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-darwin-x86_64"
      sha256 "72f85fd24a15874613abd306eb57b612bdc9a67c2b374c31fc829d6345b91638"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-aarch64"
      sha256 "77e8292cb8e73b93e7f666273a88d5073347519532a7a0637e1de8c192f305c8"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-x86_64"
      sha256 "8745688a70cff2b05929c43a1dc38b39795436945b2fc3245ed41b7924248aee"
    end
  end

  def install
    bin.install Dir["swamp-*"].first => "swamp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swamp --version")
  end
end
