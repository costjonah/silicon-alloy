class SiliconAlloy < Formula
  desc "Apple Silicon-friendly Wine distribution with bottle management"
  homepage "https://github.com/your-org/silicon-alloy"
  url "https://github.com/your-org/silicon-alloy/archive/v0.1.0.tar.gz"
  sha256 "d34db33fd34db33fd34db33fd34db33fd34db33fd34db33fd34db33fd34db33f"
  license "LGPL-2.1-or-later"
  head "https://github.com/your-org/silicon-alloy.git", branch: "main"

  depends_on "pkg-config"
  depends_on "ninja"
  depends_on "cmake" => :build
  depends_on "python@3.12" => :build

  on_arm do
    depends_on arch: :x86_64
  end

  def install
    ENV["WINE_VERSION"] = "9.0"
    system "runtime/scripts/fetch_components.sh"
    system "runtime/scripts/build_wine.sh"

    dist = Dir["runtime/build/dist/wine-*"].first
    libexec.install Dir["#{dist}/*"]

    (bin/"silicon-alloy").write <<~SH
      #!/bin/bash
      exec "#{libexec}/bin/wine" "$@"
    SH
  end

  test do
    system "#{bin}/silicon-alloy", "--version"
  end
end

