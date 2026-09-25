class Slate < Formula
  desc "Small indentation-structured, garbage-collected language, written in sysl"
  homepage "https://github.com/slate-language/slate"
  version "0.1.9"
  license "ISC"

  # macOS on Apple silicon, and Linux on both x86_64 and arm64 -- built on Ubuntu
  # runners by `.github/workflows/release-linux.yml` since sysl does not
  # cross-compile. Everywhere else, build from source, which is a clone and one
  # `sysl build .`.
  on_macos do
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-#{version}-darwin-arm64.tar.gz"
      sha256 "7fd47c398519f26f77a80bc07de718e7f7a32dfbd2fdc75d03eae8a586afe3eb"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-#{version}-linux-x86_64.tar.gz"
      sha256 "c125f52de38b50932f8d8fed19de69492098a105271bcbe2a58a5154864e3cf2"
    end
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-#{version}-linux-arm64.tar.gz"
      sha256 "5df2960fcaa021f97e780c45337441fca9b7dd8d584b9ce6bfd2db2183dbda03"
    end
  end

  # No `depends_on` at all, and the census is `otool -L slate`: since 0.1.7 every
  # library that has an archive is linked statically, so the binary names only
  # /usr/lib/libSystem.B.dylib and /usr/lib/libsqlite3.dylib, neither of them
  # Homebrew's. A library added later that has no archive comes back as a dylib line
  # and owes a `depends_on` here -- a missing one installs cleanly and then fails to
  # start with a dyld error, so the census is re-read from the shipped binary at each
  # release rather than carried forward.

  def install
    # `bin.install` NAMING THE BINARY, never `prefix.install Dir["*"]` -- brew strips
    # a single top-level directory before `install` runs, so what `Dir["*"]` sees
    # depends on how the tarball happened to be rolled rather than on anything the
    # formula says.
    #
    # 0.0.1 shipped `slate-0.0.1-darwin-arm64/bin/slate`: the version directory was
    # stripped, `Dir["*"]` was `bin`, and the keg came out right by accident. 0.0.2
    # shipped `bin/slate`: `bin` itself was stripped, `Dir["*"]` was `slate`, and the
    # binary landed at `prefix/slate`, which brew links nothing from. `brew upgrade`
    # reported success and `slate` was command-not-found.
    #
    # The glob takes either layout, so a release cannot break the install by changing
    # how it tars. slate needs no library beside the executable -- the standard
    # modules are compiled in, which is what makes this shorter than sysl's own.
    bin.install Dir["slate", "bin/slate"].first
  end

  # A SMOKE TEST, NOT A SUITE. It asks the one question a formula can answer -- is the
  # binary installed, linked and able to run a program -- and nothing about the language,
  # which slate's own suite (thousands of tests, run on every commit to dev) already holds.
  # This block once grew by one assertion per release and became a second suite that
  # drifted as the language moved: two of its programs, written at 0.0.8 and 0.0.12,
  # failed `brew test` at 0.0.37 for saying things the language had stopped saying.
  test do
    # The version, which is the first thing anybody holding a binary asks.
    assert_equal "slate #{version}\n", shell_output("#{bin}/slate --version")

    # A script with a shebang, run by the kernel rather than by naming the binary: a binary
    # that starts is not the same as one the kernel can hand a script to.
    (testpath/"greet.sl").write <<~SLATE
      #!#{bin}/slate
      import { args } from slate:process

      for name in args
          print("Hello, " + name + "!")
    SLATE

    chmod 0755, testpath/"greet.sl"
    assert_equal "Hello, world!\n", shell_output("#{testpath}/greet.sl world")

    # The test runner and the JavaScript back end, each answering once.
    (testpath/"one.sl").write <<~SLATE
      @test
      adds() = assertEq(6 * 7, 42)
    SLATE

    assert_match "1 passed", shell_output("#{bin}/slate test #{testpath}/one.sl")

    (testpath/"hello.sl").write "print(6 * 7)\n"
    assert_match '$.arith("*", 6n, 7n)', shell_output("#{bin}/slate js #{testpath}/hello.sl")

    # The bound libraries, linked into the binary statically. This CALLS into four of
    # them so a library that links but answers wrongly is caught too.
    (testpath/"libs.sl").write <<~SLATE
      import { sha256 } from slate:crypto
      import { regex } from slate:regex
      import { zstd, unzstd } from slate:zstd
      import { compress, decompress } from slate:brotli

      hex(bs) = bs.toArray().map(b -> "0123456789abcdef"[b >> 4] + "0123456789abcdef"[b & 15]).join("")

      print(hex(sha256("abc")))
      print(regex("(\\\\d+)-(\\\\d+)").find("10-20").groups[2])
      print(fromBytes(unzstd(zstd(toBytes("zstd works"), 3), 4096).value).value)
      print(fromBytes(decompress(compress(toBytes("brotli works"), 5), 4096).value).value)
    SLATE

    assert_equal <<~LIBS, shell_output("#{bin}/slate #{testpath}/libs.sl")
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      20
      zstd works
      brotli works
    LIBS
  end
end
