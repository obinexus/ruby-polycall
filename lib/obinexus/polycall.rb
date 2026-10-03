# frozen_string_literal: true

require "fiddle"
require "json"
require_relative "polycall/version"

module OBINexus
  # Ruby (Fiddle) binding for the Polycall binding ABI v1 (polycall.h,
  # libpolycall >= 1.1.0). Every symbol is resolved when the library is
  # loaded; Fiddle releases the GVL during each C call, so a blocking
  # Peer#recv in one thread can be woken by Peer#cancel / Peer#close from
  # another.
  module Polycall
    PACKAGE_ROOT = File.expand_path("../..", __dir__).freeze
    DEFAULT_CONFIG = File.join(PACKAGE_ROOT, "ruby-polycallrc").freeze
    ABI_VERSION = 1

    PEER_ID_MAX = 64
    MESSAGE_ID_MAX = 64
    ENDPOINT_MAX = 128
    PEER_MAX_PAYLOAD = 1 << 20
    CALL_MAX_OUTPUT = 1 << 20
    # Peer#recv timeout meaning "until a message, cancel or close".
    WAIT_FOREVER = 0xFFFF_FFFF

    # Binding ABI v1 status codes (append-only).
    module Status
      OK = 0
      E_INVALID_ARGUMENT = -1
      E_NO_MEMORY = -2
      E_INVALID_HANDLE = -3
      E_TIMEOUT = -4
      E_TRANSPORT = -5
      E_PROTOCOL = -6
      E_NOT_FOUND = -7
      E_AUTH = -8
      E_REMOTE = -9
      E_TOO_LARGE = -10
      E_BUSY = -11
      E_CANCELLED = -12
      E_CONFIG = -13
      E_ADDRESS_IN_USE = -14
      E_UNSUPPORTED = -15
      E_PERMISSION = -16
      E_CLOSED = -17
      E_INTERNAL = -18

      # Symbolic name without asking the library (used for loader errors).
      def self.name_of(status)
        found = constants.find { |c| const_get(c) == status }
        return "POLYCALL_E_UNKNOWN" unless found

        found == :OK ? "POLYCALL_OK" : "POLYCALL_#{found}"
      end
    end

    # A failed Polycall call: the POLYCALL_* status (#status / #code), the
    # polycall_strerror text (#status_text, #status_name), the thread's
    # polycall_last_error detail (#detail) and, for #call, the remote error
    # object (#output).
    class Error < StandardError
      attr_reader :status, :status_text, :detail, :output
      alias code status

      def initialize(message, status, status_text: nil, detail: "", output: "")
        @status = Integer(status)
        @status_text = Error.utf8(status_text || Status.name_of(@status))
        @detail = Error.utf8(detail)
        @output = Error.utf8(output)
        text = "#{Error.utf8(message)}: #{@status_text} (status=#{@status})"
        text += ": #{@detail}" unless @detail.empty?
        super(text)
      end

      # @api private The library's text is UTF-8; Fiddle hands it over as
      # ASCII-8BIT, which cannot be combined with a non-ASCII UTF-8 path.
      def self.utf8(value)
        value.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      end

      # "POLYCALL_E_TIMEOUT" -- the symbolic part of polycall_strerror().
      def status_name
        @status_text.split(":", 2).first
      end
    end

    # libpolycall could not be used: not found, not loadable, missing ABI v1
    # symbols (an old 1.0 core) or polycall_ffi_abi_version() != 1.
    class LibraryError < Error
      def initialize(message, status)
        super(message, status)
      end
    end

    # A message taken from a peer node's inbox; payload is a binary String.
    Message = Struct.new(:sender, :message_id, :payload)

    UINT32 = defined?(Fiddle::TYPE_UINT32_T) ? Fiddle::TYPE_UINT32_T : -Fiddle::TYPE_INT32_T
    I = Fiddle::TYPE_INT
    P = Fiddle::TYPE_VOIDP
    Z = Fiddle::TYPE_SIZE_T
    H = Fiddle::TYPE_INT32_T
    # name => [argument types, return type] -- exactly polycall.h
    SIGNATURES = {
      polycall_get_version: [[], P],
      polycall_ffi_abi_version: [[], I],
      polycall_ffi_version: [[P, I], I],
      polycall_strerror: [[I], P],
      polycall_last_error: [[P, Z], I],
      polycall_ffi_run_config: [[P, I], I],
      polycall_ffi_describe: [[P, P, I], I],
      polycall_call: [[P, P, P, P, UINT32, P, Z, P], I],
      polycall_peer_open: [[P, P, P, P], I],
      polycall_peer_close: [[H], I],
      polycall_peer_endpoint: [[H, P, Z], I],
      polycall_peer_node_id: [[H, P, Z], I],
      polycall_peer_register: [[H, P, P], I],
      polycall_peer_unregister: [[H, P], I],
      polycall_peer_list: [[H, P, Z, P], I],
      polycall_peer_ping: [[H, P, UINT32], I],
      polycall_peer_send: [[H, P, P, Z, P, UINT32], I],
      polycall_peer_recv: [[H, UINT32, P, Z, P, Z, P, Z, P], I],
      polycall_peer_cancel: [[H], I],
      polycall_peer_health: [[H, P, Z, P], I]
    }.freeze

    module LibraryLocator
      module_function

      # Load order: explicit path, POLYCALL_LIBRARY, then the platform names
      # through the OS loader search path. No package or parent directories
      # are searched.
      def candidates(explicit_path = nil)
        configured = explicit_path || ENV.fetch("POLYCALL_LIBRARY", nil)
        if configured && !configured.empty?
          path = File.expand_path(configured)
          raise LibraryError.new("libpolycall library does not exist: #{path}", Status::E_NOT_FOUND) unless File.file?(path)

          return [path]
        end
        case RbConfig::CONFIG["host_os"]
        when /mswin|mingw|cygwin/ then %w[polycall.dll libpolycall.dll]
        when /darwin/ then %w[libpolycall.1.dylib]
        else %w[libpolycall.so.1]
        end
      end

      # Kept for compatibility with 1.0: the library that would be loaded.
      def find(explicit_path = nil)
        candidates(explicit_path).first
      end
    end

    # A loaded libpolycall (binding ABI v1).
    class Runtime
      attr_reader :library_path

      def initialize(library_path: nil)
        errors = []
        LibraryLocator.candidates(library_path).each do |candidate|
          begin
            handle = Fiddle.dlopen(candidate)
          rescue Fiddle::DLError => e
            errors << "#{candidate}: #{e.message}"
            next
          end
          @functions = resolve_all(handle, candidate)
          abi = @functions[:polycall_ffi_abi_version].call
          unless abi == ABI_VERSION
            raise LibraryError.new("#{candidate} reports binding ABI #{abi}; this binding requires ABI #{ABI_VERSION}",
                                   Status::E_UNSUPPORTED)
          end

          @handle = handle
          @library_path = candidate
          return
        end
        raise LibraryError.new("libpolycall not found; set POLYCALL_LIBRARY to its absolute path (#{errors.join('; ')})",
                               Status::E_NOT_FOUND)
      end

      # @api private
      def fn(name)
        @functions.fetch(name)
      end

      def abi_version
        fn(:polycall_ffi_abi_version).call
      end

      def version
        buf = Fiddle::Pointer.malloc(64, Fiddle::RUBY_FREE)
        n = fn(:polycall_ffi_version).call(buf, 64)
        fail!(n, "polycall_ffi_version") if n.negative?
        buf.to_s
      end

      def strerror(status)
        fn(:polycall_strerror).call(status).to_s.force_encoding(Encoding::UTF_8)
      end

      # Detail of the most recent failure on this thread ("" after success).
      def last_error
        buf = Fiddle::Pointer.malloc(1024, Fiddle::RUBY_FREE)
        fn(:polycall_last_error).call(buf, 1024)
        buf.to_s.force_encoding(Encoding::UTF_8)
      end

      # Validate one configuration file with the core grammar; returns the
      # core status unchanged. strict: true is polycall_ffi_run_config(path, 1).
      def run_config(config_path = DEFAULT_CONFIG, strict: true)
        Integer(fn(:polycall_ffi_run_config).call(cstr(config_path), strict ? 1 : 0))
      end

      def run_config!(config_path = DEFAULT_CONFIG, strict: true)
        status = run_config(config_path, strict: strict)
        fail!(status, "run_config(#{config_path.inspect})") unless status.zero?
        status
      end

      # JSON description of a configuration file (secrets never resolved).
      def describe(config_path)
        cap = 65_536
        loop do
          buf = Fiddle::Pointer.malloc(cap, Fiddle::RUBY_FREE)
          n = fn(:polycall_ffi_describe).call(cstr(config_path), buf, cap)
          fail!(n, "describe(#{config_path.inspect})") if n.negative?
          return buf.to_s(n).force_encoding(Encoding::UTF_8) if n < cap

          cap = n + 1
        end
      end

      # One polycall_rpc v1 round trip, never retried. Returns the output JSON.
      def call(endpoint, service, operation, input_json = nil, timeout_ms: 5000)
        out = Fiddle::Pointer.malloc(CALL_MAX_OUTPUT, Fiddle::RUBY_FREE)
        len = Fiddle::Pointer.malloc(Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
        status = fn(:polycall_call).call(cstr(endpoint), cstr(service), cstr(operation),
                                         input_json.nil? ? nil : cstr(input_json), uint32(timeout_ms, "timeout_ms"),
                                         out, CALL_MAX_OUTPUT, len)
        text = status == Status::E_TOO_LARGE ? "" : out.to_s.force_encoding(Encoding::UTF_8)
        fail!(status, "call #{service}.#{operation} at #{endpoint}", output: text) unless status.zero?
        text
      end

      # Open a peer node. bind: "127.0.0.1:0" = ephemeral port, nil = send-only.
      # With a block, yields the peer and closes it afterwards.
      def open_peer(node_id, bind: "127.0.0.1:0", token: nil)
        peer = Peer.open(self, node_id, bind: bind, token: token)
        return peer unless block_given?

        begin
          yield peer
        ensure
          peer.close unless peer.closed?
        end
      end

      # @api private
      def fail!(status, what, output: "")
        raise Error.new(what, status, status_text: strerror(status), detail: last_error, output: output)
      end

      # @api private NUL-terminated UTF-8 copy for a const char * argument
      def cstr(value)
        s = value.to_s.encode(Encoding::UTF_8)
        raise Error.new("argument contains NUL", Status::E_INVALID_ARGUMENT) if s.include?("\0")

        s.b + "\0"
      end

      # @api private A uint32_t argument (timeouts in ms). Fiddle would
      # silently wrap a negative Integer (-1 became WAIT_FOREVER), so the
      # range is checked here.
      def uint32(value, what)
        unless value.is_a?(Integer) && value.between?(0, WAIT_FOREVER)
          raise Error.new(what, Status::E_INVALID_ARGUMENT,
                          detail: "#{what} must be an Integer in 0..#{WAIT_FOREVER}, got #{value.inspect}")
        end

        value
      end

      private

      def resolve_all(handle, candidate)
        SIGNATURES.to_h do |name, (args, ret)|
          address = begin
            handle[name.to_s]
          rescue Fiddle::DLError => e
            raise LibraryError.new("#{candidate} is not a Polycall binding-ABI-v1 library " \
                                   "(libpolycall >= 1.1.0 required): missing symbol #{name} (#{e.message})",
                                   Status::E_UNSUPPORTED)
          end
          [name, Fiddle::Function.new(address, args, ret)]
        end
      end
    end
    Library = Runtime

    # A peer node (polycall_peer_*). Its registry and inbox belong to this
    # node only. Methods raise Error on a non-OK status; use after close is
    # POLYCALL_E_INVALID_HANDLE (defined, never a crash).
    class Peer
      attr_reader :handle

      def self.open(runtime, node_id, bind: "127.0.0.1:0", token: nil)
        out = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        status = runtime.fn(:polycall_peer_open).call(
          runtime.cstr(node_id), bind.nil? ? nil : runtime.cstr(bind),
          token.nil? || token.empty? ? nil : runtime.cstr(token), out
        )
        runtime.fail!(status, "peer open #{node_id.inspect}") unless status.zero?
        new(runtime, out[0, 4].unpack1("l"))
      end

      # Wrap an existing integer handle (stale / invalid handle tests).
      def self.from_handle(runtime, handle)
        new(runtime, handle)
      end

      def initialize(runtime, handle)
        @rt = runtime
        @handle = Integer(handle)
        unless @handle.between?(-0x8000_0000, 0x7FFF_FFFF)
          raise Error.new("peer handle", Status::E_INVALID_HANDLE,
                          detail: "#{@handle} is outside the int32 polycall_peer_t range")
        end
        @closed = false
      end

      def closed?
        @closed
      end

      # Stop the listener, wake blocked receivers (POLYCALL_E_CLOSED). A
      # second close raises POLYCALL_E_INVALID_HANDLE.
      def close
        @closed = true
        check(@rt.fn(:polycall_peer_close).call(@handle), "peer close")
        nil
      end

      def endpoint
        text_out(:polycall_peer_endpoint, ENDPOINT_MAX, "peer endpoint")
      end

      def node_id
        text_out(:polycall_peer_node_id, PEER_ID_MAX, "peer node_id")
      end

      def register(peer_id, endpoint)
        check(@rt.fn(:polycall_peer_register).call(@handle, @rt.cstr(peer_id), @rt.cstr(endpoint)),
              "peer register #{peer_id.inspect}")
        self
      end

      def unregister(peer_id)
        check(@rt.fn(:polycall_peer_unregister).call(@handle, @rt.cstr(peer_id)), "peer unregister #{peer_id.inspect}")
        self
      end

      def list_json
        sized_json(:polycall_peer_list, "peer list")
      end

      # This node's registry: { "peer-id" => "host:port" }
      def list
        JSON.parse(list_json)
      end

      def ping(peer, timeout_ms: 2000)
        check(@rt.fn(:polycall_peer_ping).call(@handle, @rt.cstr(peer), @rt.uint32(timeout_ms, "timeout_ms")),
              "peer ping #{peer.inspect}")
        true
      end

      # Deliver payload (binary-safe String, <= 1 MiB): exactly one attempt.
      # Retry with the SAME message_id; the receiver drops duplicates.
      def send(peer, payload, message_id: nil, timeout_ms: 5000)
        bytes = payload.to_s.b
        status = @rt.fn(:polycall_peer_send).call(
          @handle, @rt.cstr(peer), bytes.empty? ? nil : bytes, bytes.bytesize,
          message_id.nil? || message_id.empty? ? nil : @rt.cstr(message_id), @rt.uint32(timeout_ms, "timeout_ms")
        )
        check(status, "peer send to #{peer.inspect}")
        true
      end
      alias deliver send

      # Take the oldest message. timeout_ms 0 = poll, WAIT_FOREVER = until a
      # message, #cancel or #close. A too-small capacity raises
      # POLYCALL_E_TOO_LARGE (needed size in #output) and leaves it queued.
      # capacity must be >= 0; no message exceeds PEER_MAX_PAYLOAD, so a
      # larger capacity allocates (and passes) only PEER_MAX_PAYLOAD bytes.
      def recv(timeout_ms: WAIT_FOREVER, capacity: PEER_MAX_PAYLOAD)
        timeout = @rt.uint32(timeout_ms, "timeout_ms")
        unless capacity.is_a?(Integer) && capacity >= 0
          raise Error.new("peer recv", Status::E_INVALID_ARGUMENT,
                          detail: "capacity must be an Integer >= 0, got #{capacity.inspect}")
        end

        cap = [capacity, PEER_MAX_PAYLOAD].min
        sender = Fiddle::Pointer.malloc(PEER_ID_MAX, Fiddle::RUBY_FREE)
        mid = Fiddle::Pointer.malloc(MESSAGE_ID_MAX, Fiddle::RUBY_FREE)
        buf = Fiddle::Pointer.malloc([cap, 1].max, Fiddle::RUBY_FREE)
        len = Fiddle::Pointer.malloc(Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
        status = @rt.fn(:polycall_peer_recv).call(@handle, timeout, sender, PEER_ID_MAX, mid, MESSAGE_ID_MAX,
                                                  buf, cap, len)
        n = size_at(len)
        if status == Status::E_TOO_LARGE
          raise Error.new("peer recv", status, status_text: @rt.strerror(status),
                                               detail: "message needs #{n} bytes; buffer has #{cap} " \
                                                       "(message stays queued)",
                                               output: n.to_s)
        end
        check(status, "peer recv")
        Message.new(sender.to_s.force_encoding(Encoding::UTF_8), mid.to_s.force_encoding(Encoding::UTF_8),
                    n.zero? ? "".b : buf.to_s(n))
      end

      # Wake every #recv blocked on this node with POLYCALL_E_CANCELLED.
      def cancel
        check(@rt.fn(:polycall_peer_cancel).call(@handle), "peer cancel")
        nil
      end

      def health_json
        sized_json(:polycall_peer_health, "peer health")
      end

      def health
        JSON.parse(health_json)
      end

      private

      def size_at(pointer)
        pointer[0, Fiddle::SIZEOF_SIZE_T].unpack1(Fiddle::SIZEOF_SIZE_T == 8 ? "Q" : "L")
      end

      def text_out(function, cap, what)
        buf = Fiddle::Pointer.malloc(cap, Fiddle::RUBY_FREE)
        check(@rt.fn(function).call(@handle, buf, cap), what)
        buf.to_s.force_encoding(Encoding::UTF_8)
      end

      def sized_json(function, what)
        cap = 4096
        4.times do
          buf = Fiddle::Pointer.malloc(cap, Fiddle::RUBY_FREE)
          len = Fiddle::Pointer.malloc(Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
          status = @rt.fn(function).call(@handle, buf, cap, len)
          if status == Status::E_TOO_LARGE
            cap = size_at(len) + 1
            next
          end
          check(status, what)
          return buf.to_s(size_at(len)).force_encoding(Encoding::UTF_8)
        end
        @rt.fail!(Status::E_TOO_LARGE, what)
      end

      def check(status, what)
        @rt.fail!(status, "#{what} (handle #{@handle})") unless status.zero?
      end
    end

    module_function

    # The process-wide default runtime (loaded on first use).
    def runtime
      @runtime ||= Runtime.new
    end

    # Documented 1.0 entry point: polycall_ffi_run_config(path, 1), status unchanged.
    def run_config(config_path = DEFAULT_CONFIG, runtime: self.runtime, strict: true)
      runtime.run_config(config_path, strict: strict)
    end

    def run_config!(config_path = DEFAULT_CONFIG, runtime: self.runtime, strict: true)
      runtime.run_config!(config_path, strict: strict)
    end

    def reset_runtime!
      @runtime = nil
    end
  end
end
