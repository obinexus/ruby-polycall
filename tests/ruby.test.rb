# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "obinexus/polycall"

def assert(condition, message)
  raise message unless condition
end

runtime = OBINexus::Polycall::Runtime.new
assert(runtime.run_config("explicit-polycallrc").zero?, "explicit path failed")
assert(runtime.run_config.zero?, "default path failed")
assert(runtime.run_config("__status_37__") == 37, "status was not preserved")

begin
  runtime.run_config!("__status_37__")
  raise "expected OBINexus::Polycall::Error"
rescue OBINexus::Polycall::Error => error
  assert(error.status == 37, "exception status was not preserved")
  assert(error.code == 37, "compatibility code was not preserved")
end

assert(
  OBINexus::Polycall.run_config("explicit-polycallrc", runtime: runtime).zero?,
  "module API failed"
)

puts "ruby-polycall Fiddle smoke test: PASS"
