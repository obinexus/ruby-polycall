# TODO — ruby-polycall

Status: Ruby Fiddle binding over the Polycall binding ABI v1 (libpolycall >= 1.1.0).

- [x] Exact `polycall.h` signatures; every symbol resolved at load
- [x] Loader: `POLYCALL_LIBRARY`, then platform names; clear errors for a missing
      library, an old 1.0 core and an ABI mismatch
- [x] `run_config(path)` keeps `polycall_ffi_run_config(path, 1)`; `call`; `Peer`
- [x] `OBINexus::Polycall::Error` with status, `polycall_strerror` name, `polycall_last_error`
- [x] Gem built, installed into a clean GEM_HOME and tested outside the checkout
      (Linux, ruby:3.3) incl. interop with the C CLI peer and the PHP binding
- [ ] Windows run (no Ruby on the QA host)
- [ ] Publish `obinexus-ruby-polycall` / `@obinexusltd/ruby-polycall`
