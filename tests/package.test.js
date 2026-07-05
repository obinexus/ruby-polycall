'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const binding = require('..');
const metadata = require('../package.json');

assert.equal(metadata.name, '@obinexusltd/ruby-polycall');
assert.equal(metadata.license, 'MIT');
assert.equal(metadata.publishConfig.access, 'public');

const author = typeof metadata.author === 'string'
  ? metadata.author
  : `${metadata.author?.name} <${metadata.author?.email}>`;
assert.equal(author, 'Nnamdi Michael Okpala <okpalan@protonmail.com>');

const metadataKeys = {
  lib: 'lib',
  src: 'src',
  generated: 'generated',
  dist: 'dist',
  examples: 'example',
  tests: 'test',
  scripts: 'scripts'
};

for (const [name, directory] of Object.entries(binding.directories)) {
  const metadataKey = metadataKeys[name];
  assert.equal(metadata.directories[metadataKey], directory.relative);
  assert.equal(path.isAbsolute(metadata.directories[metadataKey]), false);
  assert.equal(fs.statSync(directory.root).isDirectory(), true);
  assert.ok(directory.files.length > 0, `${name} directory index is empty`);
  assert.ok(directory.files.every((file) => file.startsWith(`${directory.root}${path.sep}`)));
}

assert.ok(binding.directories.lib.relativeFiles.includes('obinexus/polycall.rb'));
assert.ok(binding.directories.lib.relativeFiles.includes('obinexus/polycall/version.rb'));
assert.ok(binding.directories.src.relativeFiles.includes('polycall.rb'));
assert.ok(binding.directories.examples.relativeFiles.includes('run.rb'));
assert.throws(() => binding.resolve('lib', '..', 'package.json'), RangeError);

for (const file of [
  binding.rubyLibrary,
  binding.rubyVersion,
  binding.compatibilityLoader,
  binding.ffiHeader,
  binding.gemspec,
  binding.config,
  binding.manifest
]) {
  assert.equal(path.isAbsolute(file), true, `path is not absolute: ${file}`);
  assert.equal(fs.existsSync(file), true, `missing project file: ${file}`);
}

console.log('ruby-polycall npm relative-directory index test: PASS');
