'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const required = process.argv.includes('--required');
const rubyProbe = spawnSync('ruby', ['--version'], { stdio: 'ignore' });

if (rubyProbe.error || rubyProbe.status !== 0) {
  if (required) {
    console.error('Ruby is required for this command but was not found on PATH');
    process.exit(1);
  }
  console.log('Ruby not found; skipping Ruby Fiddle smoke test');
  process.exit(0);
}

const fiddleProbe = spawnSync('ruby', ['-rfiddle', '-e', 'exit 0'], {
  stdio: 'ignore'
});
if (fiddleProbe.error || fiddleProbe.status !== 0) {
  if (required) {
    console.error('Ruby Fiddle is required but could not be loaded');
    process.exit(1);
  }
  console.log('Ruby Fiddle not available; skipping Ruby Fiddle smoke test');
  process.exit(0);
}

const buildDirectory = path.join(root, 'build');
fs.mkdirSync(buildDirectory, { recursive: true });

let libraryName;
let compilerArguments;
if (process.platform === 'win32') {
  libraryName = 'polycall_ffi_mock.dll';
  compilerArguments = ['-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-shared'];
} else if (process.platform === 'darwin') {
  libraryName = 'libpolycall_ffi_mock.dylib';
  compilerArguments = ['-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-dynamiclib'];
} else {
  libraryName = 'libpolycall_ffi_mock.so';
  compilerArguments = ['-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-shared', '-fPIC'];
}

const libraryPath = path.join(buildDirectory, libraryName);
compilerArguments.push(
  path.join('tests', 'polycall_ffi_mock.c'),
  '-o',
  libraryPath
);

const compile = spawnSync('gcc', compilerArguments, {
  cwd: root,
  stdio: 'inherit'
});
if (compile.error || compile.status !== 0) {
  console.error('failed to compile the Ruby Fiddle mock library');
  process.exit(compile.status || 1);
}

const test = spawnSync('ruby', ['-Ilib', path.join('tests', 'ruby.test.rb')], {
  cwd: root,
  env: { ...process.env, POLYCALL_LIBRARY: libraryPath },
  stdio: 'inherit'
});
if (test.error || test.status !== 0) {
  process.exit(test.status || 1);
}
