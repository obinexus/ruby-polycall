'use strict';

const fs = require('node:fs');
const path = require('node:path');

const relativeDirectories = Object.freeze({
  lib: 'lib',
  src: 'src',
  generated: 'generated',
  dist: 'dist',
  examples: 'examples',
  tests: 'tests',
  scripts: 'scripts'
});

function walkFiles(root, current = root) {
  return fs.readdirSync(current, { withFileTypes: true })
    .sort((left, right) => left.name.localeCompare(right.name))
    .flatMap((entry) => {
      const absolutePath = path.join(current, entry.name);
      return entry.isDirectory() ? walkFiles(root, absolutePath) : [absolutePath];
    });
}

function indexDirectory(relativePath) {
  const root = path.join(__dirname, relativePath);
  const files = walkFiles(root);
  return Object.freeze({
    relative: relativePath,
    root,
    files: Object.freeze(files),
    relativeFiles: Object.freeze(
      files.map((file) => path.relative(root, file).split(path.sep).join('/'))
    )
  });
}

const directories = Object.freeze(
  Object.fromEntries(
    Object.entries(relativeDirectories).map(([name, relativePath]) => [
      name,
      indexDirectory(relativePath)
    ])
  )
);

function resolve(directoryName, ...segments) {
  const directory = directories[directoryName];
  if (!directory) {
    throw new RangeError(`unknown ruby-polycall directory: ${directoryName}`);
  }

  const resolved = path.resolve(directory.root, ...segments);
  const prefix = `${directory.root}${path.sep}`;
  if (resolved !== directory.root && !resolved.startsWith(prefix)) {
    throw new RangeError(`path escapes ruby-polycall ${directoryName} directory`);
  }
  return resolved;
}

module.exports = Object.freeze({
  packageName: '@obinexusltd/ruby-polycall',
  projectRoot: __dirname,
  directories,
  resolve,
  rubyLibrary: path.join(__dirname, 'lib', 'obinexus', 'polycall.rb'),
  rubyVersion: path.join(__dirname, 'lib', 'obinexus', 'polycall', 'version.rb'),
  compatibilityLoader: path.join(__dirname, 'src', 'polycall.rb'),
  ffiHeader: path.join(__dirname, 'generated', 'polycall', 'polycall_ffi.h'),
  gemspec: path.join(__dirname, 'ruby-polycall.gemspec'),
  config: path.join(__dirname, 'ruby-polycallrc'),
  manifest: path.join(__dirname, 'polycall-binding.json')
});
