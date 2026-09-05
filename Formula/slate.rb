class Slate < Formula
  desc "Small indentation-structured, garbage-collected language, written in sysl"
  homepage "https://github.com/slate-language/slate"
  version "0.0.30"
  license "ISC"

  # macOS on Apple silicon is the only build there is. sysl does not cross-compile,
  # so a Linux binary has to be built on Linux, and nothing does that yet -- there
  # is no CI workflow for it. Rather than offer an install that cannot run, this
  # names the one platform it has; everywhere else, build from source, which is a
  # clone and one `sysl build .`.
  on_macos do
    on_arm do
      url "https://github.com/slate-language/slate/releases/download/v#{version}/slate-#{version}-darwin-arm64.tar.gz"
      sha256 "482b95b9a90fc45bef12bfeb3a6d7cac2c5f85f3e70486d39c6abedf5f69f200"
    end
  end

  # The six libraries the binary actually links, and the census is `otool -L slate`
  # rather than the dependency list in package.hocon -- miniz, monocypher, llhttp and
  # QOI are vendored C and appear in neither the link line nor here.
  #
  # A missing one installs cleanly and then fails to start, with a dyld error naming
  # a path nobody typed, so this list is re-read from the shipped binary at each
  # release rather than carried forward.
  depends_on "brotli"    # `slate:brotli`, and `Content-Encoding: br` on a response
  depends_on "hiredis"   # `slate:redis` -- the RESP reader; the socket stays slate's
  depends_on "libnghttp2" # `slate:nghttp2` -- HTTP/2 framing and HPACK, and now `slate:http` over it
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
    # that says what it ENCODES. **The spelling is 0.0.16's**: `=` rather than the `:`
    # that shipped for one release, because `greet(name: string, greeting = "hello")`
    # writes the type after a colon and the default after an equals -- so a colon here
    # would have meant the parameter's TYPE one line up and its VALUE at the call.
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

      print(greet("ada", punct = "?"), greet(greeting = "hi", name = "ada"))
      print(Rect(h = 4, w = 3), Circle(r = 7))
      print(toJSON({ shapes: [Circle(1)], paid: Money(150) }))
      print(sub(b = 1, a = 5), sub(a = 1, c = 2) catch e -> e.message)
      print(sub(5, 1) == 4)
    SLATE

    # The last line is 0.0.16's own: `==` is its own token, so a comparison written as an
    # argument stays an ordinary POSITIONAL one. A lookahead that took `=` too eagerly
    # would read `sub(5, 1) == 4` as naming something and every line above would still pass.
    assert_equal <<~NAMED, shell_output("#{bin}/slate #{testpath}/named.sl")
      hello, ada? hi, ada!
      Rect(3, 4) Circle(7)
      {"shapes":[{"r":1}],"paid":"150"}
      4 `sub` has no parameter called `c` -- it takes `a` and `b`
      true
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

    # What 0.0.17 is for: the eight methods an array was missing, and a chain of them.
    #
    # **Asserted as a CHAIN**, because that is the shape a method is written in and the one a table
    # entry alone would not prove: each link hands its answer to the next, so a method registered
    # under the wrong kind or answering the wrong thing fails here rather than somewhere quieter.
    #
    # `unshift` answering nothing is asserted on its own line, since it is where slate parts from
    # JavaScript -- there it hands back the new length, which makes the call look like it produced
    # something.
    (testpath/"methods.sl").write <<~SLATE
      val xs = [4, 1, 3, 2]

      print(xs.sorted().slice(1, 3).flatMap(n -> [n, n]).at(-1))
      print(xs.findLast(n -> n < 3), xs.findLastIndex(n -> n < 3), xs.at(-1))

      var ys = [1, 2]

      print(ys.unshift(0), ys.shift(), ys)
      ys.forEach(n -> print("saw", n))
    SLATE

    assert_equal "3\n2 3 2\nnull 0 [1, 2]\nsaw 1\nsaw 2\n",
                 shell_output("#{bin}/slate #{testpath}/methods.sl")

    # And the other half of 0.0.17: an element type survives a call, in BOTH spellings. The method
    # form is the one that said nothing before -- `xs.map(f)` is `map(xs, f)` to the interpreter and
    # was a field read off an array to the checker.
    (testpath/"elements.sl").write <<~SLATE
      f(xs: array of string) = len(xs)

      h(ns: array of integer) = f(ns.filter(n -> n > 1))

      h([1, 2])
    SLATE

    assert_match "`f` takes array of string here, and this is array of integer",
                 shell_output("#{bin}/slate #{testpath}/elements.sl", 1)

    # What 0.0.18 is for: a callback knows what it is HANDED, so the mistake is caught inside the
    # lambda's own body rather than one call later.
    #
    # 0.0.17 typed the RESULT of `map` and left `n` as `any`, so this program compiled and faulted
    # when it ran. What the message says is the tell: it names the operator and the two kinds, at
    # the multiplication, which only a pass that knew `s` was a string could do.
    (testpath/"callback.sl").write <<~SLATE
      g(ss: array of string) = map(ss, s -> s * 2)

      g(["a"])
    SLATE

    assert_match "`*` does not apply to string and integer",
                 shell_output("#{bin}/slate #{testpath}/callback.sl", 1)

    # And the half that must NOT be refused, which is the direction this pass may never be wrong in.
    # A comparator takes two elements and a bare `array` says nothing about its own, so both of
    # these run -- a release that tightened the arity or the element type too far fails here rather
    # than in somebody's program.
    (testpath/"handed.sl").write <<~SLATE
      h(ns: array of integer) = ns.sorted((a, b) -> a > b)

      print(h([2, 3, 1]))
      print(map([1, 2], n -> n * 2))
    SLATE

    assert_equal "[3, 2, 1]\n[2, 4]\n",
                 shell_output("#{bin}/slate #{testpath}/handed.sl")

    # What 0.0.19 is for: `for await`, which asks its subject for `next()` and awaits the answer.
    #
    # BOTH kinds of source in one program, because the whole design claim is that one rule covers
    # them: a generator answers `{value, done}` outright and the object answers a promise of the
    # same shape, and awaiting a value that is not a promise answers it. A binary that handled only
    # the asynchronous half would pass a test written with either one alone.
    #
    # The `else` is here too, since a loop that finished on its own is the arm with no element to
    # bind and the one most easily left out of a new loop form.
    (testpath/"await.sl").write <<~SLATE
      twoOf()
          yield 1
          yield 2

      counted(n)
          var i = 0
          val it = {}

          it.next = async () ->
              await sleep(1)

              if i >= n then { done: true, value: null }
              else
                  i += 1
                  { done: false, value: i * 10 }

          it

      async main()
          for await x in twoOf()
              print("gen", x)

          for await v in counted(2)
              print("async", v)

          val found = 'search for await v in counted(9)
              if v == 30 then break 'search v

          print("found", found)

          for await v in counted(0)
              print("never")
          else
              print("nothing arrived")

      main()
    SLATE

    assert_equal "gen 1\ngen 2\nasync 10\nasync 20\nfound 30\nnothing arrived\n",
                 shell_output("#{bin}/slate #{testpath}/await.sl")

    # And the refusal, which is the half a binary could get wrong while running every line above.
    # An array has no `next()`, and the sentence names the `await` rather than a method the program
    # never wrote -- that wording is the whole reason the guard instruction exists.
    (testpath/"walked.sl").write <<~SLATE
      async main()
          for await x in [1, 2]
              print(x)

      main()
    SLATE

    assert_match "write `for` without `await` to walk an array",
                 shell_output("#{bin}/slate #{testpath}/walked.sl", 1)

    # What 0.0.20 is for: a type written INLINE, wherever a type is wanted.
    #
    # Five things in one program, because each is a different part of the binary and any one could
    # be missing while the others work: a function type is a new pattern node the parser reads only
    # in a type position, brackets that GROUP are the same node reached another way, an annotation
    # on a binding is a statement the parser generates beside it, a type parameter is solved in the
    # checker and erased in the machine, and a generic type is substituted while compiling.
    #
    # `Pair.name()` is here because a generic type still binds a VALUE -- the shape with nothing
    # filled in -- which is the piece most easily lost when the arguments became a compiling-time
    # thing.
    (testpath/"typed.sl").write <<~SLATE
      type Pair[A, B] = { first: A, second: B }

      first[T](xs: array of T) -> T = xs[0]
      apply(f: integer -> integer) -> integer = f(1)
      keep(xs: array of (string | null)) = len(xs)
      show(p: Pair[string, integer]) = s"${p.first}=${p.second}"

      val tags: array of string = ["reading", "writing"]
      var count: integer = 0

      count += 1

      print(first(tags), apply(n -> n + 41), keep(["a", null]), count)
      print(show({ first: "a", second: 1 }), Pair.name())
    SLATE

    assert_equal "reading 42 2 1\na=1 Pair\n",
                 shell_output("#{bin}/slate #{testpath}/typed.sl")

    # And the half that shows up as something REFUSED. An annotated `var` is TypeScript's `let`, so
    # the assignment is checked against what the name was declared -- and this is the one place the
    # checker refuses a program the machine would have run, which makes it exactly the assertion a
    # binary could pass everything above without.
    (testpath/"declared.sl").write <<~SLATE
      var n: integer = 0

      n = "later"
    SLATE

    assert_match "`n` was declared integer, and this is string",
                 shell_output("#{bin}/slate #{testpath}/declared.sl", 1)

    # What 0.0.21 is for, under the name 0.0.22 gave it: HTTP/2. The module is `slate:nghttp2` and
    # not `slate:h2` -- named for the library as `slate:llhttp` is, with the protocol's own names
    # inside it -- so this doubles as the assertion that the rename actually shipped.
    # A whole request and its answer, driven between two sessions in
    # THIS process -- no socket, no port, nothing that can hang in a brew test -- which is the
    # module's own design rather than a convenience of the test: a session is a transformation of
    # bytes that never learns where they came from.
    #
    # The three assertions are three different parts of the binary and any one could be missing
    # while the others work: the framing session, HPACK on its own, and the refusal a server gives a
    # client that never heard of h2. The last is the one that says the failure channel is right --
    # bytes the peer got wrong are an ANSWER, because a fault would take a server down with one bad
    # connection.
    #
    # It also proves the sixth dylib is there: `libnghttp2` is new in this release, and a formula
    # missing it installs cleanly and then dies with a dyld error naming a path nobody typed.
    (testpath/"h2.sl").write <<~SLATE
      import { h2Client, h2Server, h2Receive, h2Send, h2Next, h2Request, h2Respond } from slate:nghttp2
      import { hpackDeflater, hpackInflater, hpackDeflate, hpackInflate } from slate:nghttp2

      val c = h2Client()
      val s = h2Server()

      pump(from, to)
          val bytes = h2Send(from)

          if len(bytes) > 0 then h2Receive(to, bytes)

      seen(who)
          var out = []

          loop
              val e = h2Next(who)

              if e == null then break

              push(out, e)

          out

      h2Request(c, { ":method": "GET", ":scheme": "https", ":authority": "a.test", ":path": "/things" })
      pump(c, s)

      for e in seen(s)
          if e.kind == "headers" then h2Respond(s, e.stream, { ":status": "200" }, "answered " + e.headers[3][1])

      pump(s, c)

      for e in seen(c)
          if e.kind == "data" then print(fromBytes(e.bytes).value)

      print(hpackInflate(hpackInflater(), hpackDeflate(hpackDeflater(), { ":status": "200" })))
      print(h2Receive(h2Server(), toBytes("GET / HTTP/1.1\r\n\r\n")).error != "")
    SLATE

    assert_equal "answered /things\n[[\":status\", \"200\"]]\ntrue\n",
                 shell_output("#{bin}/slate #{testpath}/h2.sl")

    # What 0.0.23 is for: a response that arrives in pieces, and `sse` over it. No
    # socket and no port -- `sse` answers an ordinary response VALUE whose body is a
    # source, so what it framed can be read here without anything listening.
    #
    # Three parts of the release in one file and any one could be missing while the
    # others work: the source protocol (`for await` over a generator the handler
    # answered), the SSE framing, and `percentDecode`, which `slate:http` did not
    # export until now. The keyword field name is the fourth and is the one thing
    # here that is a change to the PARSER rather than to a module.
    (testpath/"stream.sl").write <<~SLATE
      import { sse, percentDecode } from slate:http

      ticks()
          yield { event: "tick", id: 1, data: { n: 1 } }
          yield "two"

      val r = sse(ticks(), { heartbeat: 0 })
      val o = { with: 1, if: 2 }

      print(r.status, r.headers["Content-Type"], r.heartbeat)
      print(o.with, o.if, percentDecode("caf%C3%A9", false))

      async main()
          for await piece in r.body
              print(toJSON(piece))

      main()
    SLATE

    assert_equal "200 text/event-stream 0\n1 2 caf\u00e9\n" \
                 "\"event: tick\\nid: 1\\ndata: {\\\"n\\\":1}\\n\\n\"\n" \
                 "\"data: two\\n\\n\"\n",
                 shell_output("#{bin}/slate #{testpath}/stream.sl")

    # A `data` name as a SHAPE VALUE, which is what 0.0.24 is for. It is one of the
    # few features that cannot be smoke-tested by a program merely running: the name
    # bound before this release, and `Failure.test` faulted with "`test` is not a
    # field of this object" -- so what proves the binary has it is the ANSWER rather
    # than the absence of a complaint.
    #
    # The `shape`-annotated parameter is asserted with it, because that is the half a
    # program actually uses: a framework takes the type and asks it about a value,
    # and an annotation refusing a data name would leave the three methods unreachable
    # from anything that declared what it wanted.
    (testpath/"shapes.sl").write <<~SLATE
      data Failure
          NotFound(what)
          Empty

      class Point
          var x
          var y

      fits(s: shape, v) = s.test(v)

      print(Failure.name(), Failure.test(Empty), Failure.test(3))
      print(fits(Point, Point(1, 2)), fits(Failure, NotFound("a")))
      print(Point.mismatch(3))
      print(Point, Failure, print)
    SLATE

    assert_equal "Failure true false\ntrue true\n" \
                 "[{path: \"\", wanted: \"Point\", got: \"integer\"}]\n" \
                 "<class Point> <data Failure> <function>\n",
                 shell_output("#{bin}/slate #{testpath}/shapes.sl")

    # SSE over HTTP/2, which is what 0.0.25 is for. 0.0.24 could speak h2 and could
    # stream over 1.1, and the one thing it refused was the two together: a response
    # whose body arrives a piece at a time went out over h2 as a single DATA frame at
    # the end, or not at all.
    #
    # **The whole exchange, over a real loopback socket with a real ALPN handshake**,
    # because every layer here could be present while the release's own change was
    # missing: `slate:net` negotiates `h2`, `slate:nghttp2` frames it, `slate:http`
    # answers the route, and only the last of them knows how to hand a source over
    # frame by frame. What is asserted is the body a client actually read off the
    # DATA frames, not what the server thought it wrote.
    system Formula["openssl@3"].opt_bin/"openssl", "req",
           "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
           "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
           "-keyout", testpath/"h2key.pem", "-out", testpath/"h2cert.pem"

    (testpath/"h2sse.sl").write <<~SLATE
      import { serve, sse, router } from slate:http
      import { connect, send, onBytes, close, localPort, startTls } from slate:net
      import { h2Client, h2Receive, h2Send, h2Next, h2Request, h2Close } from slate:nghttp2
      import { readFileSync } from slate:fs

      val theCert = readFileSync("#{testpath}/h2cert.pem").value
      val theKey = readFileSync("#{testpath}/h2key.pem").value

      ticking()
          yield { event: "tick", id: 1, data: { n: 1 } }
          yield "two"

      val app = router()

      app.get("/events", (req) -> sse(ticking(), { heartbeat: 0 }))

      val server = serve({ port: 0, cert: theCert, key: theKey, alpn: ["h2"] }, app)

      async main()
          val c = (await connect("localhost", localPort(server))).value
          val h = h2Client()

          pump()
              val out = h2Send(h)

              if len(out) > 0 then send(c, out)

          var body = ""
          var kind = ""

          arrived(chunk)
              if chunk == null then return

              h2Receive(h, chunk)

              loop
                  val e = h2Next(h)

                  if e == null then break

                  if e.kind == "headers"
                      for [name, value] in e.headers
                          if name == "content-type" then kind = value

                  if e.kind == "data" then body = body + fromBytes(e.bytes).value

                  if e.kind == "streamClose"
                      print(kind)
                      print(toJSON(body))

                      h2Close(h)
                      close(c)
                      close(server)

                      return

              pump()

          onBytes(c, arrived)

          await startTls(c, { host: "localhost", trust: theCert, alpn: ["h2"] })

          h2Request(h, { ":method": "GET", ":scheme": "https", ":authority": "localhost", ":path": "/events" })
          pump()

      main()
    SLATE

    assert_equal "text/event-stream\n" \
                 "\"event: tick\\nid: 1\\ndata: {\\\"n\\\":1}\\n\\ndata: two\\n\\n\"\n",
                 shell_output("#{bin}/slate #{testpath}/h2sse.sl")

    # A password hashed on the THREAD POOL, which is what 0.0.26 is for. `hash`,
    # `hashStrong` and `check` answer promises now: the derivation is deliberately a
    # tenth of a second, and on the loop that was a tenth of a second in which the
    # server answered nobody.
    #
    # The `await`s are what a binary one release behind would fail on -- there `hash`
    # answers the record itself, so `check` would be handed a promise and refuse it by
    # name. And a round trip rather than a fixed vector, because the salt is sixteen
    # fresh bytes from the kernel per call: two records of one password differ, and
    # each verifies only its own.
    (testpath/"login.sl").write <<~SLATE
      import { hash, check, needsRehash } from slate:password

      async main()
          val stored = await hash("correct horse")

          print(startsWith(stored, "$argon2id$"))
          print(await check(stored, "correct horse"))
          print(await check(stored, "wrong"))
          print(needsRehash(stored))

      main()
    SLATE

    assert_equal "true\ntrue\nfalse\nfalse\n",
                 shell_output("#{bin}/slate #{testpath}/login.sl")

    # The two refusals 0.0.26 adds, which are the other half of what it is for and are
    # the cheapest thing here to check: both are decided while compiling, so neither
    # runs anything.
    #
    # **The REFUSAL is what is asserted for each**, because a checker is judged by what
    # it will not let you write -- and a binary missing either change accepts the
    # program and prints an answer, which is the failure this catches.
    (testpath/"excess.sl").write <<~SLATE
      type Style = { color: string }

      use(s: Style) = s.color

      print(use({ colour: "red" }))
    SLATE

    assert_match "did you mean `color`?",
                 shell_output("#{bin}/slate #{testpath}/excess.sl", 1)

    (testpath/"pair.sl").write <<~SLATE
      pair[T](a: T, b: T) -> array of T = [a, b]

      print(pair(1, "x"))
    SLATE

    assert_match "`T` is integer from an argument before this one, and this is string",
                 shell_output("#{bin}/slate #{testpath}/pair.sl", 1)

    # `slate:gzip`, which is what 0.0.27 is for -- the compression a browser has where
    # brotli is not, and the reason the release exists. The ROUND TRIP is asserted
    # rather than the refusal alone: it is the compressor being present that a broken
    # build would lose, and a test that proves less to avoid one `async main()` is the
    # wrong trade.
    #
    # **Every name here answers a PROMISE on both back ends**, `CompressionStream` being
    # a stream with no synchronous door -- so this is the first block here that awaits
    # anything, which is worth seeing work in a real install.
    #
    # The two magic bytes are pinned rather than the stream: two deflate implementations
    # agree about the format and not about the bytes, so a length or a byte sequence
    # would be asserting on the compressor's mood. The refusal is the other half -- the
    # gzip container is parsed by slate rather than by the host, so it is slate's own
    # sentence that has to come back.
    (testpath/"gz.sl").write <<~SLATE
      import { gzip, gunzip } from slate:gzip

      async main()
          val text = repeat("slate compresses this. ", 40)
          val small = await gzip(text)
          val back = await gunzip(small, 65536)

          print(small[0], small[1], len(small) < len(toBytes(text)))
          print(fromBytes(back.value).value == text)
          print((await gunzip(toBytes("this is plainly not a gzip stream at all"), 4096)).error)

      main()
    SLATE

    assert_equal "31 139 true\ntrue\n" \
                 "this does not begin with gzip's two magic bytes, so it is not a gzip stream\n",
                 shell_output("#{bin}/slate #{testpath}/gz.sl")

    # `slate:url`, which is what 0.0.28 is for -- a module that did not exist before,
    # so a binary built from the wrong commit fails here at the IMPORT rather than at
    # an assertion, which is exactly the failure this release could have.
    #
    # The percent-coder and the `name=value` grammar were `slate:http`'s and moved down
    # a layer because a browser page importing that module to reach two functions grew
    # by 239 KB -- a file server and an HTTP/2 speaker, downloaded to read a query
    # string. `slate:http` still exports all four, and the last line asserts that: a
    # move that had quietly broken the old spelling would pass everything above it.
    #
    # `%C3%A9` is two bytes that are one character, so it is the input that separates a
    # decoder collecting BYTES from one working a character at a time.
    (testpath/"url.sl").write <<~SLATE
      import { parseQuery, percentDecode, encodeComponent } from slate:url
      import { parseQuery as httpQuery } from slate:http

      val q = parseQuery("name=Ada+Lovelace&tag=caf%C3%A9&a=1&a=2")

      print(q.name, q.tag, q.a)
      print(percentDecode("/who/caf%C3%A9", false))
      print(encodeComponent("a b/c?d=e&f"))
      print(httpQuery("x=1&y=two+words").y)
    SLATE

    assert_equal "Ada Lovelace café 2\n" \
                 "/who/café\n" \
                 "a%20b%2Fc%3Fd%3De%26f\n" \
                 "two words\n",
                 shell_output("#{bin}/slate #{testpath}/url.sl")

    # base64url, which is what 0.0.29 is for. It joins `slate:url`, so a binary built
    # from the wrong commit fails at the IMPORT rather than at an assertion -- which
    # is exactly the failure a release adding two names to an existing module has.
    #
    # RFC 4648 SS10's own vectors rather than a round trip: an encoder that agreed
    # with its own decoder and with nothing else would pass a round trip happily and
    # write tokens nobody else can read. The `-_` line is the two characters that are
    # the whole difference from base64, and they are the two a URL would otherwise
    # have to percent-encode.
    #
    # The refusal is asserted too, because the decoder answers a RESULT rather than
    # faulting -- text encoded this way arrives from outside -- and the sentence names
    # the character, which is the half a binary could lose while still decoding.
    (testpath/"b64.sl").write <<~SLATE
      import { base64urlEncode, base64urlDecode } from slate:url

      print(base64urlEncode("foobar"), base64urlEncode("fooba"), base64urlEncode("f"))
      print(base64urlEncode([251, 255]), base64urlEncode([255, 255, 255]))

      val r = base64urlDecode("Zm9vYmFy")

      print(r.ok, fromBytes(r.value).value)
      print(base64urlDecode("ab*d").error)
    SLATE

    assert_equal "Zm9vYmFy Zm9vYmE Zg\n" \
                 "-_8 ____\n" \
                 "true foobar\n" \
                 "`*` is not a base64url character\n",
                 shell_output("#{bin}/slate #{testpath}/b64.sl")

    # An ASSET IMPORT, which is what 0.0.30 is for. It is the one thing here that needs a
    # SECOND FILE beside the program, so a binary built from the wrong commit fails at the
    # import rather than at an assertion -- and the file is read while the program is
    # compiled, so what this proves is that the shipped binary reads it at all.
    #
    # `without` rides along because it is the release's other new name and costs a line.
    (testpath/"panel.css").write ".panel { display: grid; }\n"

    (testpath/"assets.sl").write <<~SLATE
      import styles from "./panel.css"

      print(len(styles), trim(styles))
      print(without({ a: 1, b: 2 }, "a"))
    SLATE

    assert_equal "26 .panel { display: grid; }\n{b: 2}\n",
                 shell_output("#{bin}/slate #{testpath}/assets.sl")

    # And the REFUSAL, which is the half a binary could get wrong while running the program
    # above: the extension is the whole rule, so a `.css` asked for names has to say so
    # rather than being handed to the lexer and reported as a syntax error in somebody's CSS.
    (testpath/"wrong.sl").write "import { helper } from \"./panel.css\"\n"

    assert_match "is not slate source, so there are no names in it to take",
                 shell_output("#{bin}/slate #{testpath}/wrong.sl", 1)
  end
end
