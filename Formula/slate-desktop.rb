class SlateDesktop < Formula
  desc "Small indentation-structured, garbage-collected language, desktop edition (adds slate:window)"
  homepage "https://github.com/slate-language/slate"
  version "0.1.20"
  license "ISC"

  # The desktop edition is slate built with the `desktop` feature list -- the default
  # features plus `webview` -- and its binary is still called `slate`, so it and the
  # `slate` formula cannot both be installed. macOS on Apple silicon only: Linux is not
  # a release platform until 0.2.0.
  depends_on :macos

  on_macos do
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-desktop-#{version}-darwin-arm64.tar.gz"
      sha256 "35202f6fe786346f07ba4b5311d1e0831f653d777ba4ae26ccd62b34957db752"
    end

    # The census (`otool -L slate`) is the standard edition's two system lines plus
    # exactly one: /opt/homebrew/opt/webview/lib/libwebview.0.12.dylib. WebKit is
    # libwebview's own load command, not slate's. Re-read it off the shipped binary at
    # each release.
    depends_on "sysl-lang/tap/webview"
  end

  conflicts_with "slate", because: "both install bin/slate"

  def install
    # Naming the binary, never `prefix.install Dir["*"]` -- see `slate.rb` for why.
    bin.install Dir["slate", "bin/slate"].first
  end

  # A SMOKE TEST, and it must never open a window: a `brew test` shell is not at the
  # console, and a window started from one waits for ever rather than failing.
  test do
    assert_equal "slate #{version}\n", shell_output("#{bin}/slate --version")

    (testpath/"hello.sl").write "print(6 * 7)\n"
    assert_equal "42\n", shell_output("#{bin}/slate #{testpath}/hello.sl")
  end
end
