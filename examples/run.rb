# frozen_string_literal: true

# ruby -Ilib examples/run.rb [config-path]
# Validates a configuration file with the core (polycall_ffi_run_config(path, 1)).
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "obinexus/polycall"

config_path = ARGV.fetch(0, OBINexus::Polycall::DEFAULT_CONFIG)

begin
  runtime = OBINexus::Polycall.runtime
  puts "libpolycall #{runtime.version} (binding ABI #{runtime.abi_version}) from #{runtime.library_path}"
  OBINexus::Polycall.run_config!(config_path)
  puts "configuration is valid for running: #{config_path}"
rescue OBINexus::Polycall::Error => e
  warn e.message
  exit 1
end
