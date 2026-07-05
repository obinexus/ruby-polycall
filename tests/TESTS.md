# Tests

- `package.test.js` validates npm metadata, RubyGems layout, author, license,
  exports, and every project-relative directory index.
- `source.test.js` enforces the single-function Fiddle boundary and rejects
  configuration parsing or unrelated core APIs.
- `ruby.test.rb` exercises raw statuses, default paths, the module API, and
  `OBINexus::Polycall::Error` against a generated mock shared library.
