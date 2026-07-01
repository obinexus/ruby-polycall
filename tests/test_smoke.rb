# ruby-polycall smoke test. Requires the shared core to be built first.
# Run:  ruby -I../src tests/test_smoke.rb   (auto-skips if the lib isn't built)
$LOAD_PATH.unshift File.expand_path(File.join(__dir__, "..", "src"))
require "polycall"

begin
  raise "version mismatch" unless Polycall.version == "1.5.0"
  Polycall.run_config(nil, run: true)
  puts "ruby-polycall smoke: PASS (#{Polycall.version})"
rescue Polycall::Error => e
  if e.code == 6
    puts "shared libpolycall not built; skipping (#{e.message})"
    exit 0
  end
  warn "ruby-polycall smoke: FAIL #{e.message}"
  exit 1
end
