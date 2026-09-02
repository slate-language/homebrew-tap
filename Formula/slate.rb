class Slate < Formula
  desc "Small indentation-structured, garbage-collected language, written in sysl"
  homepage "https://github.com/slate-language/slate"
  version "0.0.15"
  license "ISC"

  # macOS on Apple silicon is the only build there is. sysl does not cross-compile,
  # so a Linux binary has to be built on Linux, and nothing does that yet -- there
  # is no CI workflow for it. Rather than offer an install that cannot run, this
  # names the one platform it has; everywhere else, build from source, which is a
  # clone and one `sysl build .`.
  on_macos do
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-#{version}-darwin-arm64.tar.gz"
      sha256 "966578691f00c00f683b918942a09ea365ac145cc7a1397f888d0f48746b02c0"
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

    # Subpath imports, which is what 0.0.3 is for. A `/` in an unquoted specifier used to be a
    # parse error at the slash; what proves the binary has the feature is that it now parses,
    # resolves as a PACKAGE, and complains about the package rather than about the punctuation.
    #
    # The refusal is asserted rather than a working import, because a working one needs a fetch --
    # and a formula test that reaches the network fails for reasons that are not the binary's.
    (testpath/"sub.sl").write "import { domHost } from lath/dom\n"

    assert_match "nothing this project depends on is called `lath`",
                 shell_output("#{bin}/slate #{testpath}/sub.sl", 1)

    # `slate:crypto`, which is what 0.0.4 is for. A PUBLISHED vector rather than a
    # round trip: a digest compared against what the binary itself answered would
    # pass on a broken build just as happily, and the point of a hash is that
    # everybody else's agrees.
    #
    # `randomBytes` is asserted separately because it is the half that cannot be
    # written in slate at any price -- it reads the kernel, so a build where that
    # call is missing fails here and nowhere else.
    (testpath/"digest.sl").write <<~SLATE
      import { sha256, randomBytes } from slate:crypto

      hex(bs) = bs.map(b -> "0123456789abcdef"[b >> 4] + "0123456789abcdef"[b & 15]).join("")

      print(hex(sha256("abc")))
      print(len(randomBytes(16)))
    SLATE

    assert_equal "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n16\n",
                 shell_output("#{bin}/slate #{testpath}/digest.sl")

    # `startTls` and a `connect` that takes a NAME, which is what 0.0.5 is for -- and
    # both halves of one exchange, since neither is worth much alone: a client that
    # can upgrade but must dial an address has nothing to check a certificate against.
    #
    # A real handshake over a real loopback socket, against a listener this same
    # binary is running, on a certificate written here rather than committed -- a
    # formula test cannot reach the network and should not want to. The certificate
    # names `localhost`, which is what `startTls` is then given and what the whole
    # test turns on: `trust` adds it to the machine's store, and the name is verified
    # against it.
    system Formula["openssl@3"].opt_bin/"openssl", "req",
           "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
           "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
           "-keyout", testpath/"key.pem", "-out", testpath/"cert.pem"

    (testpath/"tls.sl").write <<~SLATE
      import { listen, connect, onData, send, close, localPort, startTls } from slate:net
      import { readFileSync } from slate:fs

      val cert = readFileSync("#{testpath}/cert.pem").value
      val key = readFileSync("#{testpath}/key.pem").value

      serve(conn)
          heard(chunk)
              if chunk == null
                  close(conn)
              else
                  send(conn, "echo: " + chunk)

          onData(conn, heard)

      val server = listen({ port: 0, cert: cert, key: key }, serve)

      async main()
          val c = (await connect("localhost", localPort(server))).value

          reply(chunk)
              print(chunk)
              close(c)
              close(server)

          onData(c, reply)

          val up = await startTls(c, { host: "localhost", trust: cert })

          print("secured " + string(up.ok))
          await send(c, "hello")

      main()
    SLATE

    assert_equal "secured true\necho: hello\n",
                 shell_output("#{bin}/slate #{testpath}/tls.sl")

    # `md5`, which is what 0.0.6 is for -- the digest PostgreSQL's older login asks
    # for, and which `slate-language/pg` wrote out in slate until this release.
    #
    # A published vector again, and one either side of the 64-byte block boundary:
    # 55 bytes pads inside one block and 56 needs a second, so an implementation
    # that got the padding wrong answers the short vectors correctly and nothing
    # else. `pbkdf2` is asserted beside it because this release stopped computing
    # it here and asks the standard library instead -- RFC 6070's first case, so a
    # derivation that silently changed would be caught rather than trusted.
    (testpath/"md5.sl").write <<~SLATE
      import { md5, pbkdf2 } from slate:crypto

      hex(bs) = bs.map(b -> "0123456789abcdef"[b >> 4] + "0123456789abcdef"[b & 15]).join("")

      print(hex(md5("abc")))
      print(hex(md5("12345678901234567890123456789012345678901234567890123456")))
      print(hex(pbkdf2("SHA-1", "password", "salt", 1, 20)))
    SLATE

    assert_equal "900150983cd24fb0d6963f7d28e17f72\n" \
                 "49f193adce178490e34d1b3a4ec0064c\n" \
                 "0c60c80f961f0e71f3a9b524af6012062fe037a6\n",
                 shell_output("#{bin}/slate #{testpath}/md5.sl")

    # A declared type as a VALUE, which is what 0.0.7 is for, together with the two
    # pattern forms that shipped with it -- `?` for a field a value need not have and
    # `&` for the intersection of two shapes.
    #
    # All three in one program, because each is a different part of the binary and
    # any one could be missing while the others work: `?` is the lexer and the
    # matcher, `&` is the parser and the precedence ladder, and the shape is a new
    # `Value` with a table behind it. What is asserted is a `mismatch` REPORT rather
    # than a boolean -- it names the path, what was wanted and what arrived, so a
    # walk that answered no for the wrong reason would not pass.
    (testpath/"shape.sl").write <<~SLATE
      type Note = { title: string, pinned?: boolean }
      type Authed = { user: string } & Note

      print(Note.name(), Note is shape)
      print(Note.test({ title: "a" }), Note.test({ title: "a", pinned: 1 }))
      print(toJSON(Note.mismatch({ pinned: 1 })))
      print(Authed.test({ user: "u", title: "a" }), Authed.test({ title: "a" }))
    SLATE

    assert_equal <<~REPORT, shell_output("#{bin}/slate #{testpath}/shape.sl")
      Note true
      true false
      [{"path":"title","wanted":"string","got":"nothing"},{"path":"pinned","wanted":"boolean","got":"integer"}]
      true false
    REPORT

    # `array of T`, a rest parameter and an operator a class answers for, which is what 0.0.8 is
    # for. All three in one program, because each is a different part of the binary and any one
    # could be missing while the others work: `array of T` is a pattern node and a matcher,
    # `...rest` is the parser plus the gather every call path shares, and an operator hook is a
    # lookup `arith` only reaches after everything else has declined.
    #
    # What is asserted for the first is a `mismatch` REPORT rather than a boolean -- an array
    # pattern already answered `true` for `["a", 2] is [string, ...]`, so a boolean would pass on
    # the very thing this release exists to fix.
    (testpath/"widen.sl").write <<~SLATE
      type Tags = array of string

      class Money
          var cents

          plus(self, o) = Money(self.cents + o.cents)
          compare(self, o) = self.cents - o.cents

      total(first, ...rest) =
          var sum = first

          for m in rest
              sum = sum + m

          sum

      print(Tags.test(["a", "b"]), Tags.test(["a", 2]), Tags.test([]))
      print(toJSON(Tags.mismatch(["a", 2])))
      print(total(Money(1)).cents, total(Money(1), Money(2), Money(3)).cents)
      print(Money(1) < Money(2), Money(2) < Money(1))
    SLATE

    assert_equal <<~WIDE, shell_output("#{bin}/slate #{testpath}/widen.sl")
      true false true
      [{"path":"1","wanted":"string","got":"integer"}]
      1 6
      true false
    WIDE

    # The four modules written in slate carry ANNOTATIONS and export the shapes they
    # hand out, which is what 0.0.9 is for -- together with the four checker bugs
    # that writing them found.
    #
    # **What is asserted is that this program COMPILES AT ALL.** Every line of it was
    # refused by 0.0.8: a type declaration could not name `Request` (or any other
    # imported type), `{ value?: any }` demanded the key anyway, and `at` stayed
    # `integer | null` past the guard that returned on it. Refusing a program that
    # runs is the one mistake that pass may not make, so the compile is the test.
    #
    # The printed answers are here so that a binary which merely stopped complaining,
    # without narrowing anything, would fail too.
    (testpath/"checked.sl").write <<~SLATE
      import { Request } from slate:http

      type Handled = { req: Request, who: string }
      type Reply = { ok: boolean, value?: any, error?: string }

      said(r: Reply) = if r.ok then string(r.value) else r.error

      pick(xs: array of string, i: integer) -> string = xs[i]

      find(xs: array of string, want: string) -> string
          val at = indexOf(xs, want)

          if at == null then return "none"

          pick(xs, at)

      print(Handled.name(), Request is shape)
      print(said({ ok: true, value: 41 }), said({ ok: false, error: "no" }))
      print(find(["a", "b"], "b"), find(["a"], "z"))
    SLATE

    assert_equal "Handled true\n41 no\nb none\n",
                 shell_output("#{bin}/slate #{testpath}/checked.sl")

    # The object model, which is what 0.0.10 is for. Every line of this was a
    # different answer in 0.0.9: a class printed the object it desugars to, `eq`,
    # `ne` and `toString` were not names at all, `equals` written as a method died on
    # its arity, and `keys` reported the tag the declaration wrote.
    #
    # `==` staying content-based for a class is asserted too. Identity for a nominal
    # value was built during this release and withdrawn, so it is exactly the sort of
    # thing a later one could reintroduce by accident.
    (testpath/"objects.sl").write <<~SLATE
      class Point
          var x
          var y

      class Money
          var cents

          equals(self, o) = o is Money && self.cents == o.cents
          toString(self) = "$" + string(self.cents)

      val p = Point.new(1, 2)

      print(p, Point)
      print(p == Point.new(1, 2), p.eq(Point.new(1, 2)), p.eq(p), p.ne(p))
      print(Money.new(150), Money.new(150) == Money.new(150))
      print((42).toString(), [1, 2].equals([1, 2]), keys(Point))
    SLATE

    assert_equal "Point(x = 1, y = 2) <class Point>\ntrue false true false\n$150 true\n42 true [\"new\"]\n",
                 shell_output("#{bin}/slate #{testpath}/objects.sl")

    # What 0.0.11 is for: the two back ends saying one thing. Both halves are asserted
    # here because both were wrong in one back end only, which is the shape of defect a
    # single-back-end test cannot see -- and the JavaScript half is what `slate js`
    # plus node checks, which no other assertion in this formula reaches.
    (testpath/"parity.sl").write <<~SLATE
      class Money
          var cents

          toString(self) = "$" + string(self.cents)

      var t = {}

      t[[1, 2]] = "array key"
      t[{ a: 1 }] = "object key"

      print(t[[1, 2]], t[{ a: 1 }], len(t), keys(t))

      // A diagnostic renders a value WITHOUT the class's own `toString`, where the
      // program renders it with one. Both back ends draw that line in the same place.
      print(Money.new(150), (Money.new(150) match
          1 -> "one") catch e -> e.message)
    SLATE

    want = "array key object key 2 [[1, 2], {a: 1}]\n" \
           "$150 no arm of this match applies to Money(cents = 150)\n"

    assert_equal want, shell_output("#{bin}/slate #{testpath}/parity.sl")

    # What 0.0.12 is for: ONE suite, run by both back ends, out of this one binary.
    #
    # The four assertions in it are the divergences that release closed, one apiece:
    # ASCII case, a mutator answering nothing, `fromBytes` answering a result, and a
    # real surviving a JSON round trip as a real. They are asserted against the
    # INTERPRETER here; the `--js` half moved down to 0.0.14's assertion, which needs
    # node and says so when there is none.
    (testpath/"both.sl").write <<~SLATE
      @test
      case_is_ascii_only() = assertEq(upper("h\u{e9}llo"), "H\u{e9}LLO")

      @test
      a_mutator_answers_nothing() =
          var xs = [1]

          assertEq(push(xs, 2), null)
          assertEq(xs, [1, 2])

      @test
      from_bytes_answers_a_result() = assertEq(fromBytes(toBytes("hi")).value, "hi")

      @test
      async a_real_survives_json_as_a_real() =
          assertEq(toJSON(1.0), "1.0")
          assert(parseJSON(toJSON(1.0)).value is real)
          assertEq(await 7, 7)
    SLATE

    assert_match "4 passed", shell_output("#{bin}/slate test #{testpath}/both.sl")

    # And the version the binary reports, which is the first thing anybody holding one
    # asks. It is written by hand in two places, so a release that bumped one of them
    # ships a binary that misreports itself.
    assert_equal "slate #{version}\n", shell_output("#{bin}/slate --version")

    # What 0.0.13 is for: an ASYNCHRONOUS suite under `--js`. An embedded realm has no
    # timers of its own -- quickjs keeps its two on a module it cannot reach -- so
    # `sleep` and `setTimeout` were dead there, and every test written against them
    # failed for want of a host rather than for anything it asserted.
    #
    # The two runs are NOT compared as text here, unlike the one above: the harness
    # drives a virtual clock, so the interpreter reports the milliseconds it really
    # slept and the engine reports none. That difference is the feature working. What
    # is asserted is the verdict, on both.
    (testpath/"timed.sl").write <<~SLATE
      @test
      async a_timer_resumes_the_program_later() =
          var seen = []

          setTimeout(() -> push(seen, "timer"), 10)
          push(seen, "now")

          await sleep(20)

          assertEq(seen, ["now", "timer"])

      @test
      async a_continuation_runs_before_a_timer_already_due() =
          var seen = []

          setTimeout(() -> push(seen, "timer"), 0)

          await resolve(0)

          push(seen, "promise")

          await sleep(10)

          assertEq(seen, ["promise", "timer"])
    SLATE

    assert_match "2 passed", shell_output("#{bin}/slate test #{testpath}/timed.sl")

    # What 0.0.14 is for: `slate test --js` runs on NODE, and slate links no JavaScript
    # engine any more. quickjs was a dependency of this formula for exactly one release
    # and getting rid of it is most of the point -- so this asserts the feature still
    # works with nothing but node, which is where slate programs actually run.
    #
    # `node` may not be on a build machine, so its absence is reported as a SKIP of this
    # one assertion rather than a failure of the formula: what a brew test is for is the
    # binary, and slate's own suite is where the back ends are held together.
    if which("node")
      assert_match "2 passed", shell_output("#{bin}/slate test --js #{testpath}/timed.sl")
    else
      assert_match "node could not be started",
                   shell_output("#{bin}/slate test --js #{testpath}/timed.sl", 1)
    end

    # What 0.0.15 is for: an argument that says which parameter it fills, and a class
    # that says what it ENCODES.
    #
    # Both in one program, because each is a different part of the binary and either
    # could be missing while the other works: a named argument is the parser, a new
    # instruction and the arrangement `invoke` does with it, and `toJSON` is a hook
    # looked up the way `toString` already was.
    #
    # `greet("ada", punct: "?")` is the case the feature earns its place with -- a
    # default in the MIDDLE, which is the one thing a positional call cannot say. And
    # the data variants are asserted through `toJSON` rather than `print`, because
    # every class instance and every data variant was unencodable before this release:
    # the walk reached the class object and complained about a function nobody wrote.
    #
    # The refusal is here too, since a binary that took a name and quietly ignored it
    # would pass every line above.
    (testpath/"named.sl").write <<~SLATE
      class Money
          var cents

          toJSON(self) = string(self.cents)

      data Shape
          Circle(r)
          Rect(w, h)

      greet(name, greeting = "hello", punct = "!") = greeting + ", " + name + punct

      sub(a, b) = a - b

      print(greet("ada", punct: "?"), greet(greeting: "hi", name: "ada"))
      print(Rect(h: 4, w: 3), Circle(r: 7))
      print(toJSON({ shapes: [Circle(1)], paid: Money(150) }))
      print(sub(b: 1, a: 5), sub(a: 1, c: 2) catch e -> e.message)
    SLATE

    assert_equal <<~NAMED, shell_output("#{bin}/slate #{testpath}/named.sl")
      hello, ada? hi, ada!
      Rect(3, 4) Circle(7)
      {"shapes":[{"r":1}],"paid":"150"}
      4 `sub` has no parameter called `c` -- it takes `a` and `b`
    NAMED

    # And the checker following a `var`, which is the half of 0.0.15 that shows up as
    # something REFUSED rather than something written.
    #
    # 0.0.14 ran this and faulted at the call; 0.0.15 never runs it. The complaint is
    # what tells the two apart -- a run-time fault would say `x` was declared, and this
    # says which argument of which call is wrong, before anything executed.
    (testpath/"follows.sl").write <<~SLATE
      g(n: integer) = n

      h() =
          var x = "s"

          x = "t"
          g(x)

      h()
    SLATE

    assert_match "`g` takes integer here, and this is string",
                 shell_output("#{bin}/slate #{testpath}/follows.sl", 1)
  end
end
