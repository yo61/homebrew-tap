class Talhelper < Formula
  # Adopted after budimanjojo archived the upstream repository on 2026-08-26.
  # v3.1.17 is the FINAL release; homebrew-core deprecated its formula the same
  # day and disables it on 2027-08-26, after which `brew install talhelper`
  # stops working. This tap keeps the install route alive.
  #
  # homebrew-core built this from source. This installs the published binaries
  # instead, because the tree will never change again: nothing is gained by
  # keeping a Go toolchain current to rebuild a frozen release, and the release
  # assets stay downloadable from an archived repository indefinitely.
  desc "Configuration helper for Talos clusters"
  homepage "https://budimanjojo.github.io/talhelper/latest/"
  license "BSD-3-Clause"

  # The version is scanned from the URLs rather than declared. v3.1.17 is the
  # last release there will ever be, so there is nothing to keep in sync.
  livecheck do
    skip "Upstream is archived; v3.1.17 is the final release."
  end

  on_macos do
    on_arm do
      url "https://github.com/budimanjojo/talhelper/releases/download/v3.1.17/talhelper_darwin_arm64.tar.gz"
      sha256 "cf86526d730010193d3e858f13242e5f0c94fdcefe5e001716c552211b1e95b0"
    end
    on_intel do
      url "https://github.com/budimanjojo/talhelper/releases/download/v3.1.17/talhelper_darwin_amd64.tar.gz"
      sha256 "29dec70a5b2049058e4adf5ff6f236ca74fb51500ebb8e41e381ad1d49d60a09"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/budimanjojo/talhelper/releases/download/v3.1.17/talhelper_linux_arm64.tar.gz"
      sha256 "1841915ec6f533ef653baedc5f1cbf68683e0ca9a72f240ac2f257d94f68798b"
    end
    on_intel do
      url "https://github.com/budimanjojo/talhelper/releases/download/v3.1.17/talhelper_linux_amd64.tar.gz"
      sha256 "dff9162569004637b6a842c4020d909b0ffbc7fbbe2fca23a754708db95be204"
    end
  end

  def install
    bin.install "talhelper"

    # The release tarball carries only LICENSE, README.md and the binary — no
    # completions — but talhelper generates its own, so nothing is lost by not
    # building from source.
    generate_completions_from_executable(bin/"talhelper", shell_parameter_format: :cobra)
  end

  test do
    assert_match "talhelper version #{version}", shell_output("#{bin}/talhelper --version")
    assert_match "#compdef talhelper", shell_output("#{bin}/talhelper completion zsh")
  end
end
