# @obinexusltd/ruby-polycall

Ruby `Fiddle` source binding for
[libpolycall](https://github.com/obinexus/libpolycall) 1.5, packaged for public
distribution through npmjs.org.

The binding declares only `polycall_ffi_run_config`, passes a UTF-8
configuration path with validation mode `1`, and returns the core status
unchanged. Configuration parsing and runtime behavior stay inside libpolycall.

## Install from npm

```powershell
npm install @obinexusltd/ruby-polycall
```

The npm package contains portable Ruby source, RubyGems metadata, the generated
FFI declaration, examples, tests, configuration, and documentation. It does
not bundle a platform-specific libpolycall library.

## Requirements

- Ruby 2.7 or newer
- Ruby's standard `fiddle` library
- A libpolycall shared library exporting `polycall_ffi_run_config`

Set the shared-library path explicitly for reliable deployment:

```powershell
$env:POLYCALL_LIBRARY = 'C:\path\to\libpolycall.dll'
```

Without `POLYCALL_LIBRARY`, the adapter searches the package and its parent
workspace under `build`, `bin`, and `lib` using common platform library names.

## Ruby API

```ruby
require "obinexus/polycall"

status = OBINexus::Polycall.run_config("ruby-polycallrc")
exit status unless status.zero?
```

For exception-oriented startup code:

```ruby
begin
  OBINexus::Polycall.run_config!("ruby-polycallrc")
rescue OBINexus::Polycall::Error => error
  warn "libpolycall status: #{error.status}"
end
```

- `run_config(path)` returns the core status unchanged.
- `run_config!(path)` raises `OBINexus::Polycall::Error` when nonzero.
- Omitting the path uses this package's `ruby-polycallrc`.
- `Runtime.new(library_path: path)` selects a specific shared library.
- `Error#code` remains an alias for `Error#status` for compatibility.

The original `src/polycall.rb` entry point remains as a compatibility loader
and exposes `Polycall` as an alias for `OBINexus::Polycall`.

## RubyGems compatibility

[`ruby-polycall.gemspec`](ruby-polycall.gemspec) provides a conventional gem
named `obinexus-ruby-polycall`:

```powershell
gem build ruby-polycall.gemspec
```

No third-party Ruby gems are required.

## Test

```powershell
npm test
```

The mandatory tests validate npm metadata, RubyGems layout, relative directory
indexing, and the one-function Fiddle boundary. When Ruby is on `PATH`, the
suite compiles a mock shared library with GCC and exercises the real Ruby
Fiddle call automatically.

Ruby is not installed in the current tool environment, so that smoke test is
reported as skipped. Require it explicitly after installing Ruby:

```powershell
npm run test:ruby
```

## Run the example

```powershell
ruby -Ilib examples/run.rb ruby-polycallrc
```

## JavaScript build-tool entry point

```js
const binding = require('@obinexusltd/ruby-polycall');

console.log(binding.rubyLibrary);
console.log(binding.directories.lib.relativeFiles);
console.log(binding.resolve('examples', 'run.rb'));
```

All `package.json` directory metadata is project-relative. The CommonJS entry
point converts it to absolute paths and rejects traversal outside each indexed
directory.

## Publish publicly

```powershell
npm pack --dry-run
npm publish --access public
```

`publishConfig.access` is already `public`. Publishing is not automatic.

## Author and license

Nnamdi Michael Okpala (`okpalan@protonmail.com`). Licensed under MIT.
