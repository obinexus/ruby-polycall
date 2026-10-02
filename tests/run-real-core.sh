#!/bin/sh
# ruby-polycall: build the gem, install it into a clean GEM_HOME and run the
# minitest suite from OUTSIDE the checkout against the REAL installed core.
#
#   sh tests/run-real-core.sh [minitest args, e.g. --verbose]
#
# Needs Ruby >= 3.1 (fiddle, minitest), a C compiler and the core
# (POLYCALL_PREFIX, default /opt/polycall; or POLYCALL_LIBRARY plus
# `polycall` on PATH). Exit: 0 pass, 1 failure, 77 SKIPPED (a missing
# toolchain is never reported as success).
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)
command -v ruby >/dev/null 2>&1 || { echo "SKIP: ruby not found on PATH"; exit 77; }
command -v gem >/dev/null 2>&1 || { echo "SKIP: gem not found on PATH"; exit 77; }
ruby -rfiddle -e 'exit 0' 2>/dev/null || { echo "SKIP: Ruby's fiddle is not available"; exit 77; }
ruby -rminitest -e 'exit 0' 2>/dev/null || { echo "SKIP: minitest is not installed"; exit 77; }
. tests/real-core-env.sh

GEMFILE="$POLYCALL_TEST_TMP/obinexus-ruby-polycall.gem"
gem build ruby-polycall.gemspec --output "$GEMFILE" || { echo "FAIL: gem build"; exit 1; }
GEM_HOME="$POLYCALL_TEST_TMP/gem-home"
export GEM_HOME
gem install --local --no-document "$GEMFILE" || { echo "FAIL: gem install into a clean GEM_HOME"; exit 1; }
mkdir -p "$POLYCALL_TEST_TMP/outside"
cd "$POLYCALL_TEST_TMP/outside" || exit 1
POLYCALL_TEST_DIR="$REPO/tests/real_core" ruby \
  -e 'Dir[File.join(ENV.fetch("POLYCALL_TEST_DIR"), "test_*.rb")].sort.each { |f| require f }' -- "$@"
