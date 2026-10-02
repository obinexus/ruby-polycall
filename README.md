# ruby-polycall

Ruby binding for the [Polycall](https://github.com/obinexus/polycall) core's
**binding ABI v1** (`polycall.h`, libpolycall >= 1.1.0), through Ruby's
standard `Fiddle`: configuration validation, `polycall_rpc` calls and
peer-to-peer nodes. Gem `obinexus-ruby-polycall`; npm distribution
`@obinexusltd/ruby-polycall` (neither is published yet).

The binding declares the exact C signatures from `polycall.h`
(`OBINexus::Polycall::SIGNATURES`) and resolves every symbol when the library
is loaded. Fiddle releases the GVL during each C call, so a `Peer#recv`
blocked in one thread can be woken by `#cancel` or `#close` from another.

## Requirements

- Ruby >= 3.1 (`fiddle`, `json`)
- the Polycall core >= 1.1.0 installed (`libpolycall.so.1`, `polycall.dll` /
  `libpolycall.dll`, or `libpolycall.1.dylib`)

## Loading the library

`OBINexus::Polycall::Runtime.new` tries, in order: `library_path:`, then
`POLYCALL_LIBRARY` (an explicit file; a path that does not exist is an error),
then the platform name through the OS loader search path (`polycall.dll`,
`libpolycall.dll` / `libpolycall.so.1` / `libpolycall.1.dylib`). No package or
parent directory is searched. A missing library, an old 1.0 core without the
ABI v1 symbols, or `polycall_ffi_abi_version() != 1` raises
`OBINexus::Polycall::LibraryError` naming the library and the problem.

## API

```ruby
require "obinexus/polycall"

rt = OBINexus::Polycall::Runtime.new        # or OBINexus::Polycall.runtime
rt.abi_version                              # => 1
rt.version                                  # => "1.1.0"

# configuration -- the documented entry point, polycall_ffi_run_config(path, 1)
OBINexus::Polycall.run_config("ruby-polycallrc")    # => 0, or the raw status
OBINexus::Polycall.run_config!("ruby-polycallrc")   # raises OBINexus::Polycall::Error
rt.run_config("ruby-polycallrc", strict: false)     # run=0: unknown keys are warnings
rt.describe("ruby-polycallrc")                      # JSON text

# one polycall_rpc round trip to `polycall start` / `polycall daemon start`
rt.call("127.0.0.1:8084", "inventory", "get", '{"item_id":"widget-a"}', timeout_ms: 2000)

# peer nodes
rt.open_peer("alpha", bind: "127.0.0.1:0", token: ENV["POLYCALL_DEV_TOKEN"]) do |alpha|
  alpha.register("beta", "127.0.0.1:9002")
  alpha.send("beta", "binary\0safe", message_id: "msg-1", timeout_ms: 5000)
  message = alpha.recv(timeout_ms: 5000)   # Message(sender, message_id, payload [BINARY])
  alpha.ping("beta"); alpha.list; alpha.health; alpha.endpoint; alpha.node_id
  alpha.unregister("beta"); alpha.cancel
end                                         # closed by the block
```

Every failure raises `OBINexus::Polycall::Error`: `#status` / `#code` is the
`POLYCALL_E_*` code (constants in `OBINexus::Polycall::Status`),
`#status_name` / `#status_text` come from `polycall_strerror`, `#detail` is
`polycall_last_error` (per thread), and `#output` holds the remote error
object of a failed `#call`. `recv(capacity:)` too small raises
`POLYCALL_E_TOO_LARGE`, reports the needed size in `#output`, and leaves the
message queued. `Peer#send` (aliased `#deliver`) shadows `Object#send` like
`BasicSocket#send` does; use `__send__` for reflection.

The original `src/polycall.rb` loader still exposes `Polycall` as an alias
for `OBINexus::Polycall`.

## Tests

`tests/run-real-core.sh` builds the gem, installs it into a clean
`GEM_HOME`, and runs the minitest suite (`tests/real_core`) from **outside the
checkout** against the **real installed core**: the installed-gem check,
library/ABI checks, loader failures (missing library, old core, ABI 2),
`run_config`, `call` against a live `polycall start` runtime, two peer nodes
exchanging payloads both ways (empty, UTF-8, binary with NUL, exactly 1 MiB,
1 MiB + 1), registry ownership, de-duplication, auth, dead peers, timeouts,
small buffers, cancel and close waking blocked receivers in other threads,
handle lifecycle, concurrent senders on shared and separate handles (with
backpressure retries), and interop with a C node run by
`polycall peer serve` / `send` / `recv`. A missing Ruby, fiddle, minitest or
core is reported as SKIP (exit 77), never as success.

```sh
sh tests/run-real-core.sh --verbose   # core in /opt/polycall, or POLYCALL_PREFIX / POLYCALL_LIBRARY
```

`tests/interop/exchange.rb` is the cross-language exchange script used with
php-polycall's `tests/interop/exchange.php`.

## Author and license

Nnamdi Michael Okpala (`okpalan@protonmail.com`). MIT, see [LICENSE](LICENSE).
