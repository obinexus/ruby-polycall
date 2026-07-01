# ruby-polycall - Ruby reference adapter for libpolycall.
#
# A thin adapter over the flat FFI boundary (include/polycall/polycall_ffi.h)
# using Ruby's stdlib `fiddle` (no gems). No config parsing or runtime logic
# lives here: every method forwards to the shared C core. This is the template
# for other scripting bindings.
#
# Usage:
#   ruby -Isrc -e 'require "polycall"; puts Polycall.version'
#   ruby -Isrc src/polycall.rb ../ruby-polycallrc
require "fiddle"
require "fiddle/import"

module Polycall
  VERSION = "1.5.0"

  # Raised when the core returns a non-zero polycall_status_t.
  class Error < StandardError
    attr_reader :code
    def initialize(message, code)
      super("#{message} (status=#{code})")
      @code = code
    end
  end

  module Core
    extend Fiddle::Importer

    # Locate the shared core produced by the top-level build (setup.sh / CMake).
    def self.candidate_paths
      here = File.expand_path(File.dirname(__FILE__))
      root = File.expand_path(File.join(here, "..", "..", ".."))
      names = %w[libpolycall.dll polycall.dll libpolycall.so libpolycall.dylib]
      %w[build bin].flat_map { |d| names.map { |n| File.join(root, d, n) } }
    end

    def self.load!
      return if @loaded
      path = candidate_paths.find { |p| File.exist?(p) }
      raise Error.new("shared libpolycall not found; build the core first (./setup.sh)", 6) unless path
      dlload path
      extern "int polycall_ffi_version(char*, int)"
      extern "int polycall_ffi_run_config(const char*, int)"
      extern "int polycall_ffi_describe(const char*, char*, int)"
      @loaded = true
    end
  end

  def self.version
    Core.load!
    buf = Fiddle::Pointer.malloc(64)
    Core.polycall_ffi_version(buf, 64)
    buf.to_s
  end

  def self.run_config(path = nil, run: true)
    Core.load!
    rc = Core.polycall_ffi_run_config(path, run ? 1 : 0)
    raise Error.new("run_config(#{path.inspect})", rc) unless rc.zero?
    rc
  end

  def self.describe(path = nil)
    Core.load!
    buf = Fiddle::Pointer.malloc(256)
    rc = Core.polycall_ffi_describe(path, buf, 256)
    text = buf.to_s
    raise Error.new("describe(#{path.inspect}): #{text}", rc) unless rc.zero?
    text
  end
end

if __FILE__ == $PROGRAM_NAME
  cfg = ARGV[0]
  puts "ruby-polycall using libpolycall #{Polycall.version}"
  puts Polycall.describe(cfg)
  exit Polycall.run_config(cfg)
end
