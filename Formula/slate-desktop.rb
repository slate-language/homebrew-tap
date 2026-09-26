class SlateDesktop < Formula
  desc "Small indentation-structured, garbage-collected language, desktop edition (adds slate:window)"
  homepage "https://github.com/slate-language/slate"
  version "0.1.11"
  license "ISC"

  # The desktop edition is slate built with the `desktop` feature list -- the default
  # features plus `webview` -- and its binary is still called `slate`, so it and the
  # `slate` formula cannot both be installed.
  on_macos do
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-desktop-#{version}-darwin-arm64.tar.gz"
      sha256 "789efa2576299170034d53a03838a610c950b11ee226d48245c775da2559dc80"
    end

    # The census (`otool -L slate`) is the standard edition's two system lines plus
    # exactly one: /opt/homebrew/opt/webview/lib/libwebview.0.12.dylib. WebKit is
    # libwebview's own load command, not slate's. Re-read it off the shipped binary at
    # each release.
    depends_on "sysl-lang/tap/webview"
  end

  # On Linux libwebview is linked in from its archive, and GTK 3 and WebKitGTK 4.1 are the
  # distribution's, linked dynamically by decision: a browser engine is the system's, not
  # a thing to carry. So there is no `depends_on` here, and the machine needs
  # `libgtk-3-0` and `libwebkit2gtk-4.1-0` (see caveats).
  on_linux do
    on_intel do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-desktop-#{version}-linux-x86_64.tar.gz"
      sha256 "PENDING-slate-desktop-linux-x86_64"
    end
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-desktop-#{version}-linux-arm64.tar.gz"
      sha256 "PENDING-slate-desktop-linux-arm64"
    end
  end

  conflicts_with "slate", because: "both install bin/slate"

  def install
    # Naming the binary, never `prefix.install Dir["*"]` -- see `slate.rb` for why.
    bin.install Dir["slate", "bin/slate"].first
  end

  def caveats
    on_linux do
      <<~EOS
        The desktop edition draws its windows with the system's GTK 3 and WebKitGTK 4.1:
          sudo apt-get install libgtk-3-0 libwebkit2gtk-4.1-0
      EOS
    end
  end

  # A SMOKE TEST, and it must never open a window: a `brew test` shell is not at the
  # console, and a window started from one waits for ever rather than failing.
  test do
    assert_equal "slate #{version}\n", shell_output("#{bin}/slate --version")

    (testpath/"hello.sl").write "print(6 * 7)\n"
    assert_equal "42\n", shell_output("#{bin}/slate #{testpath}/hello.sl")
  end
end
