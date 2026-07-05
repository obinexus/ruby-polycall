# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "obinexus/polycall"

config_path = ARGV.fetch(0, OBINexus::Polycall::DEFAULT_CONFIG)

begin
  OBINexus::Polycall.run_config!(config_path)
  puts "libpolycall completed successfully"
rescue OBINexus::Polycall::Error => error
  warn error.message
  exit error.status
end
