# slate-language/homebrew-tap

The Homebrew tap for [slate](https://github.com/slate-language/slate) — a small
indentation-structured, garbage-collected language written in [sysl](https://sysl.sh).

```
brew tap slate-language/tap
brew install slate
```

**macOS on Apple silicon, and Linux on both x86_64 and arm64.** sysl does not cross-compile, so the
Linux tarballs are built on Linux runners rather than cross-compiled. Everywhere else, build slate
from source — a clone and `sysl build .`.

**0.0.59 is macOS-only.** Its Linux tarballs failed their own release-time smoke test (a `slate:regex`
bug — see `Formula/slate.rb`'s note beside the removed `on_linux` block) and were withheld rather than
shipped broken; Linux is expected back in 0.0.60.

The formula installs the release tarball as a prefix: `bin/slate` and nothing beside it, the standard
modules being compiled into the executable. It depends on the eight libraries the binary actually
links — `brotli`, `hiredis`, `libnghttp2`, `libuv`, `lmdb`, `openssl@3`, `webp` and `zstd` — which is
read from `otool -L` on the shipped binary at each release rather than from slate's own dependency
list, most of slate's C being vendored and linked statically.
