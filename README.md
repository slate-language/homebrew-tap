# slate-language/homebrew-tap

The Homebrew tap for [slate](https://github.com/slate-language/slate) — a small
indentation-structured, garbage-collected language written in [sysl](https://sysl.sh).

```
brew tap slate-language/tap
brew install slate
```

**macOS on Apple silicon only.** sysl does not cross-compile, so a Linux binary has to be built on
Linux and nothing does that yet; the formula names the one platform it has rather than offering an
install that cannot run. Everywhere else, build slate from source — a clone and `sysl build .`.

The formula installs the release tarball as a prefix: `bin/slate` and nothing beside it, the standard
modules being compiled into the executable. It depends on the five libraries the binary actually
links — `brotli`, `hiredis`, `libuv`, `openssl@3` and `pcre2` — which is read from `otool -L` on the
shipped binary at each release rather than from slate's own dependency list, most of slate's C being
vendored and linked statically.
