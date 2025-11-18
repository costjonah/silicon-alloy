class SiliconAlloy < Formula
  desc "Apple Silicon-friendly Wine distribution with bottle tooling"
  homepage "https://github.com/your-org/silicon-alloy"
  url "https://example.com/silicon-alloy-0.1.0.tar.gz"
  sha256 "replace-with-sha256"
  license "LGPL-2.1-or-later"

  depends_on arch: :arm64
  depends_on "zstd"

  def install
    prefix.install Dir["*"]
    bin.install_symlink prefix/"core/target/release/silicon-alloy"
  end

  def caveats
    <<~EOS
      silicon alloy ships an x86_64 wine runtime that relies on rosetta.
      install rosetta first:

        softwareupdate --install-rosetta
    EOS
  end

  test do
    assert_match "silicon-alloy", shell_output("#{bin}/silicon-alloy --version")
  end
end

