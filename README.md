# ruby-polycall

**Ruby** binding for [libpolycall](https://github.com/obinexus/libpolycall) — an
implemented reference adapter.

A thin adapter over the flat FFI boundary (`polycall_ffi.h`). It contains no
config or runtime logic; every call forwards to the shared C core. See
[../../docs/adapter-pattern.md](../../docs/adapter-pattern.md).

## Build & run

```bash
cd ../.. && ./setup.sh          # build the shared core (build/libpolycall.*)
cd bindings/ruby-polycall
ruby -Isrc src/polycall.rb ruby-polycallrc
ruby -Isrc tests/test_smoke.rb
```

Uses Ruby stdlib `fiddle` (no gems).

## Config

Read-only config: [`ruby-polycallrc`](ruby-polycallrc) — the standard `*polycallrc` convention on
the single shared schema. No per-language parser exists.

## Manifest

See [`polycall-binding.json`](polycall-binding.json).
