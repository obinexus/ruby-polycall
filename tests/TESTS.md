# Tests

- `run-real-core.sh` — the real-core runner. Sources `real-core-env.sh`
  (locates the installed core, builds the loader-failure fixtures, starts a
  `polycall start` runtime, sets a random `POLYCALL_DEV_TOKEN`), runs
  `gem build`, installs the gem into a clean `GEM_HOME`, and runs minitest
  over `real_core/` from a directory outside the checkout. Exit 77 = SKIPPED
  (no Ruby / fiddle / minitest / core), never success.
- `real_core/test_library.rb` — the installed gem is the one loaded, version +
  ABI check, `polycall_strerror` names, per-thread `polycall_last_error`,
  `POLYCALL_LIBRARY`, missing library, old core, ABI 2, 1.0 module API.
- `real_core/test_config_and_call.rb` — `run_config` valid / missing / invalid /
  strict unknown key / unsupported TLS, `describe`; `polycall_call` success,
  unknown operation, remote error object, deadline, invalid input, no
  runtime, concurrent calls.
- `real_core/test_peer.rb` — two nodes both directions, payload matrix,
  registry ownership, duplicate id, auth, dead peer, receive timeout,
  too-small buffer, cancel and close waking blocked receivers (threads),
  handle lifecycle, invalid ids, concurrent senders (shared + separate
  handles, backpressure retried with the same id).
- `real_core/test_interop.rb` — Ruby node <-> `polycall peer serve` C node, both
  directions, CLI `register` / `health` against the Ruby node, `call` parity
  with the CLI client.
- `real_core/test_boundaries.rb` — timeouts outside `uint32` and negative
  capacities rejected (not wrapped), capacity clamping at 1 MiB, `int32`
  handles, a non-ASCII configuration path, the platform-name loader path
  (found / not found via `LD_LIBRARY_PATH`), and the GVL: other Ruby threads
  run while `recv` / `call` block in the core.
- `interop/exchange.rb` — cross-language exchange script (pairs with
  php-polycall's `tests/interop/exchange.php`).
- `fixtures/fake_polycall.c` — loader-failure fixture only (old core, ABI 2).
- `package.test.js` — npm / gemspec / binding-manifest metadata (no Ruby).
