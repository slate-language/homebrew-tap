class Slate < Formula
  desc "Small indentation-structured, garbage-collected language, written in sysl"
  homepage "https://github.com/slate-language/slate"
  version "0.0.2"
  license "ISC"

  # macOS on Apple silicon is the only build there is. sysl does not cross-compile,
  # so a Linux binary has to be built on Linux, and nothing does that yet -- there
  # is no CI workflow for it. Rather than offer an install that cannot run, this
  # names the one platform it has; everywhere else, build from source, which is a
  # clone and one `sysl build .`.
  on_macos do
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-#{version}-darwin-arm64.tar.gz"
      sha256 "a849755b6ba32dde85c0cbd5c778ad62c98a818eb3b12a6d01a0fe02232bdb2f"
    end
  end

  # The five libraries the binary actually links, and the census is `otool -L slate`
  # rather than the dependency list in package.hocon -- miniz, monocypher, llhttp and
  # QOI are vendored C and appear in neither the link line nor here.
  #
  # A missing one installs cleanly and then fails to start, with a dyld error naming
  # a path nobody typed, so this list is re-read from the shipped binary at each
  # release rather than carried forward.
  depends_on "brotli"    # `slate:brotli`, and `Content-Encoding: br` on a response
  depends_on "hiredis"   # `slate:redis` -- the RESP reader; the socket stays slate's
  depends_on "libuv"     # the event loop everything asynchronous is built on
  depends_on "openssl@3" # TLS, for `serve` over https and for `fetch`
  depends_on "pcre2"     # `slate:regex`, which is Perl's dialect rather than POSIX's

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

  test do
    # A shebang script run BY NAME, which is what this release is for. The `#!` line
    # names the keg's own binary, so this needs nothing on the PATH -- and it is the
    # one thing a formula could get wrong while installing perfectly: a binary that
    # starts is not the same as a binary the kernel can hand a script to.
    (testpath/"greet.sl").write <<~SLATE
      #!#{bin}/slate
      import { args, exit } from slate:process

      if args.len() == 0
          print("usage: greet <name>...")
          exit(2)

      for name in args
          print("Hello, " + name + "!")
    SLATE

    chmod 0755, testpath/"greet.sl"

    # assert_equal rather than assert_match, so this pins the whole of stdout rather
    # than passing on the text appearing somewhere in it.
    assert_equal "Hello, world!\nHello, slate!\n",
                 shell_output("#{testpath}/greet.sl world slate")

    # The status a script chose for itself, which a diff of the output alone would
    # miss -- and the second half of what "slate is a scripting language" means.
    assert_equal "usage: greet <name>...\n", shell_output("#{testpath}/greet.sl", 2)

    # Deliberately more than a smoke test of the binary starting. `slate test` is the
    # test runner, and running it over a file that asserts something computed reaches
    # the lexer, the compiler, the machine and the driver's exit status at once.
    (testpath/"arith.sl").write <<~SLATE
      @test
      six_times_seven_is_forty_two()
          assertEq(6 * 7, 42)
    SLATE

    assert_match "1 passed", shell_output("#{bin}/slate test #{testpath}/arith.sl")

    # The JavaScript back end, which is the other half of what `slate` ships and the
    # one part that could be missing while everything above passed.
    #
    # What is asserted is the emitted CALL and not an answer: every operator goes
    # through the runtime, slate's integer being 64 bits and JavaScript's number not,
    # so `6 * 7` is emitted as the multiplication rather than folded to 42.
    (testpath/"hello.sl").write "print(6 * 7)\n"

    assert_match '$.arith("*", 6n, 7n)', shell_output("#{bin}/slate js #{testpath}/hello.sl")

    # `slate:dom`, which is what 0.0.2 is for and the one thing above that could be
    # missing while everything else passed -- a module lives in three lists, and one
    # of them not knowing about it is a binary that compiles a page into nothing.
    #
    # The REFUSAL is what is asserted, because there is no document in a brew test
    # and the sentence is the module working: it resolves, the import is accepted,
    # the name is declared, and only the call says there is no page here.
    (testpath/"page.sl").write <<~SLATE
      import { byId } from slate:dom

      byId("app")
    SLATE

    assert_match "needs a document, and the interpreter has none",
                 shell_output("#{bin}/slate #{testpath}/page.sl", 1)
  end
end
