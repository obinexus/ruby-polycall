'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const sourcePath = path.resolve(__dirname, '..', 'lib', 'obinexus', 'polycall.rb');
const source = fs.readFileSync(sourcePath, 'utf8');

assert.match(source, /handle\["polycall_ffi_run_config"\]/);
assert.match(source, /@run_config\.call\(pointer, 1\)/);
assert.match(source, /raise Error\.new/);
assert.doesNotMatch(source, /polycall_ffi_(?:version|describe)/);
assert.doesNotMatch(
  source,
  /\b(?:File\.read|File\.open|IO\.read|TCPSocket|UDPSocket)\b/
);

console.log('ruby-polycall thin Fiddle source test: PASS');
