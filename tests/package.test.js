'use strict';

// Package-metadata test (no Ruby needed): npm, gemspec and binding manifest
// are consistent and every exported path exists. The binding itself is tested
// against the real core by tests/run-real-core.sh.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const binding = require('..');
const metadata = require('../package.json');
const manifest = require('../polycall-binding.json');

const repo = 'https://github.com/obinexus/ruby-polycall';

assert.equal(metadata.name, '@obinexusltd/ruby-polycall');
assert.equal(metadata.license, 'MIT');
assert.equal(metadata.publishConfig.access, 'public');
assert.equal(metadata.repository.url, `git+${repo}.git`);
assert.equal(metadata.bugs.url, `${repo}/issues`);
assert.equal(metadata.homepage, `${repo}#readme`);
assert.equal(manifest.version, metadata.version, 'binding manifest version matches package.json');
assert.equal(manifest.core, 'polycall >= 1.1.0 (binding ABI 1)');
assert.equal(manifest.core_repository, 'https://github.com/obinexus/polycall');

const version = fs.readFileSync(binding.rubyVersion, 'utf8');
assert.match(version, new RegExp(`VERSION = "${metadata.version.replace(/\./g, '\\.')}"`),
  'OBINexus::Polycall::VERSION matches package.json');
const gemspec = fs.readFileSync(binding.gemspec, 'utf8');
assert.match(gemspec, /spec\.name = "obinexus-ruby-polycall"/);
assert.match(gemspec, new RegExp(`spec\\.homepage = "${repo}"`));
const source = fs.readFileSync(binding.rubyLibrary, 'utf8');
assert.match(source, /run_config\(config_path = DEFAULT_CONFIG, strict: true\)/);
assert.doesNotMatch(source, /workspace_root|File\.expand_path\("\.\.", PACKAGE_ROOT\)/,
  'no blind parent-directory library search');

const author = typeof metadata.author === 'string'
  ? metadata.author
  : `${metadata.author?.name} <${metadata.author?.email}>`;
assert.equal(author, 'Nnamdi Michael Okpala <okpalan@protonmail.com>');

const metadataKeys = { lib: 'lib', src: 'src', dist: 'dist', examples: 'example', tests: 'test' };
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
  binding.gemspec,
  binding.config,
  binding.manifest
]) {
  assert.equal(path.isAbsolute(file), true, `path is not absolute: ${file}`);
  assert.equal(fs.existsSync(file), true, `missing project file: ${file}`);
}

console.log('ruby-polycall package metadata test: PASS');
