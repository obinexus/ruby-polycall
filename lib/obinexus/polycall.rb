# frozen_string_literal: true

require "fiddle"
require_relative "polycall/version"

module OBINexus
  module Polycall
    PACKAGE_ROOT = File.expand_path("../..", __dir__).freeze
    DEFAULT_CONFIG = File.join(PACKAGE_ROOT, "ruby-polycallrc").freeze
    LIBRARY_NAMES = %w[
      libpolycall.dll
      polycall.dll
      libpolycall.so
      libpolycall.dylib
    ].freeze

    class Error < StandardError
      attr_reader :status
      alias code status

      def initialize(message, status)
        @status = Integer(status)
        super("#{message} (status=#{@status})")
      end
    end

    module LibraryLocator
      module_function

      def find(explicit_path = nil)
        configured = explicit_path || ENV["POLYCALL_LIBRARY"]
        if configured && !configured.empty?
          path = File.expand_path(configured)
          raise Error.new("libpolycall library does not exist: #{path}", 6) unless File.file?(path)

          return path
        end

        workspace_root = File.expand_path("..", PACKAGE_ROOT)
        candidates = [PACKAGE_ROOT, workspace_root].flat_map do |root|
          %w[build bin lib].flat_map do |directory|
            LIBRARY_NAMES.map { |name| File.join(root, directory, name) }
          end
        end
        path = candidates.find { |candidate| File.file?(candidate) }
        return path if path

        raise Error.new(
          "shared libpolycall not found; set POLYCALL_LIBRARY to its absolute path",
          6
        )
      end
    end

    class Runtime
      def initialize(library_path: nil)
        @library_path = LibraryLocator.find(library_path)
        handle = Fiddle.dlopen(@library_path)
        address = handle["polycall_ffi_run_config"]
        @run_config = Fiddle::Function.new(
          address,
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_INT
        )
        @handle = handle
      rescue Fiddle::DLError => error
        raise Error.new("unable to load libpolycall: #{error.message}", 6)
      end

      attr_reader :library_path

      def run_config(config_path = DEFAULT_CONFIG)
        encoded_path = String(config_path).encode(Encoding::UTF_8)
        pointer = Fiddle::Pointer[encoded_path + "\0"]
        Integer(@run_config.call(pointer, 1))
      end

      def run_config!(config_path = DEFAULT_CONFIG)
        status = run_config(config_path)
        raise Error.new("libpolycall failed for #{config_path.inspect}", status) unless status.zero?

        status
      end
    end

    module_function

    def runtime
      @runtime ||= Runtime.new
    end

    def run_config(config_path = DEFAULT_CONFIG, runtime: self.runtime)
      runtime.run_config(config_path)
    end

    def run_config!(config_path = DEFAULT_CONFIG, runtime: self.runtime)
      runtime.run_config!(config_path)
    end

    def reset_runtime!
      @runtime = nil
    end
  end
end
