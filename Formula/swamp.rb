class Swamp < Formula
  desc "AI Native Automation CLI"
  homepage "https://github.com/swamp-club/swamp"
  version "20260618.203951.0-sha.b7e831fc"
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
      sha256 "58e6b5b6983698207fa78787652bc25cacf1c76d19ea64774ec3d83cdab4fdab"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-darwin-x86_64"
      sha256 "df67970d0acec8017a85218cf3ea056a89e6812e365ab1b04aee6bae57092f9e"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-aarch64"
      sha256 "c4fdd98e3967d57f05b6de4a839e0502344df9cbff2dae2075a7ddf34064bf49"
    end
    on_intel do
      url "https://github.com/swamp-club/swamp/releases/download/v#{version}/swamp-linux-x86_64"
      sha256 "b4105d23b7611087fe4a9e44fccd029409cdd86e33168349ff403e595c26a334"
    end
  end

  def install
    bin.install Dir["swamp-*"].first => "swamp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swamp --version")
  end
end
