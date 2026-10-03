#!/bin/sh
# ruby-polycall: package checks against the REAL installed core.
#
#   sh tests/run-package.sh
#
# 1. gem build, gem install into a clean GEM_HOME, use the INSTALLED gem from
#    outside the checkout and run the examples it ships;
# 2. npm pack, install the tarball into a clean temporary npm project, load
#    its JS entry point and run the packaged Ruby examples.
# Needs ruby (fiddle), gem, npm/node and the core (POLYCALL_PREFIX, default
# /opt/polycall). Exit: 0 pass, 1 failure, 77 SKIPPED.
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)
for tool in ruby gem npm node; do
  command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not found on PATH"; exit 77; }
done
. tests/real-core-env.sh
fail() { echo "FAIL: $*"; exit 1; }

echo "== gem build + install into a clean GEM_HOME"
GEMFILE="$POLYCALL_TEST_TMP/obinexus-ruby-polycall.gem"
gem build ruby-polycall.gemspec --output "$GEMFILE" || fail "gem build"
tar -xOf "$GEMFILE" data.tar.gz | tar -tzf - | sed 's/^/  /'
GEM_HOME="$POLYCALL_TEST_TMP/gem-home"
GEM_PATH="$GEM_HOME"
export GEM_HOME GEM_PATH
gem install --local --no-document "$GEMFILE" || fail "gem install"
GEMDIR=$(gem contents obinexus-ruby-polycall | sed -n 's|/lib/obinexus/polycall.rb$||p')
[ -d "$GEMDIR" ] || fail "installed gem directory not found"
mkdir -p "$POLYCALL_TEST_TMP/outside"
cd "$POLYCALL_TEST_TMP/outside" || exit 1
ruby -e '
require "obinexus/polycall"
pc = OBINexus::Polycall
loaded = $LOADED_FEATURES.grep(%r{obinexus/polycall\.rb\z})
abort "not the installed gem: #{loaded}" unless loaded.all? { |f| f.start_with?(ENV.fetch("GEM_HOME")) }
rt = pc::Runtime.new
puts "libpolycall #{rt.version} (ABI #{rt.abi_version}) from #{rt.library_path}"
abort "run_config" unless pc.run_config(pc::DEFAULT_CONFIG, runtime: rt).zero?
out = rt.call(ENV.fetch("POLYCALL_TEST_RPC_ENDPOINT"), "inventory", "get", %q({"item_id":"widget-a"}), timeout_ms: 2000)
abort "call: #{out}" unless out == %q({"item_id":"widget-a","quantity":42,"in_stock":true})
rt.open_peer("alpha") do |a|
  rt.open_peer("beta") do |b|
    a.send(b.endpoint, "bin\0ary", message_id: "pkg-1")
    m = b.recv(timeout_ms: 3000)
    abort "peer exchange: #{m.inspect}" unless m.sender == "alpha" && m.message_id == "pkg-1" && m.payload == "bin\0ary".b
  end
end
puts "installed gem: OK"' || fail "installed gem"
ruby "$GEMDIR/examples/run.rb" || fail "gem examples/run.rb"
ruby "$GEMDIR/examples/peer.rb" || fail "gem examples/peer.rb"
cd "$REPO" || exit 1

echo "== npm pack + install into a clean project"
PACKDIR="$POLYCALL_TEST_TMP/npm-pack"
mkdir -p "$PACKDIR"
TARBALL=$(npm pack --silent --pack-destination "$PACKDIR" | tail -1) || fail "npm pack"
tar -tzf "$PACKDIR/$TARBALL" | sed 's/^/  /'
NPROJ="$POLYCALL_TEST_TMP/npm-project"
mkdir -p "$NPROJ"
(cd "$NPROJ" && npm init -y >/dev/null && npm install --no-audit --no-fund "$PACKDIR/$TARBALL") || fail "npm install"
INSTALLED="$NPROJ/node_modules/ruby-polycall"
(cd "$NPROJ" && node -e '
const b = require("ruby-polycall");
if (b.packageName !== "ruby-polycall") process.exit(1);
for (const f of [b.rubyLibrary, b.gemspec, b.config]) require("fs").accessSync(f);
console.log("npm entry point:", b.rubyLibrary);') || fail "npm entry point"
unset GEM_HOME GEM_PATH
ruby "$INSTALLED/examples/run.rb" "$INSTALLED/ruby-polycallrc" || fail "packaged examples/run.rb"
ruby "$INSTALLED/examples/peer.rb" || fail "packaged examples/peer.rb"
echo "package checks: PASS"
