# frozen_string_literal: true

require "json"
require "rbconfig"
require_relative "helper"

# Integer boundaries, Unicode paths, the platform-name loader path and the
# GVL: a C call blocked in the core must not freeze other Ruby threads.
class TestBoundaries < Minitest::Test
  include RealCore

  def setup
    @open = []
  end

  def teardown
    @open.each do |peer|
      peer.close
    rescue PC::Error
      nil
    end
  end

  def node(id, bind: "127.0.0.1:0")
    runtime.open_peer(id, bind: bind).tap { |p| @open << p }
  end

  def test_timeouts_outside_uint32_are_rejected_not_wrapped
    a = node("alpha")
    [-1, 2**32, 2**64, 1.5, nil, "100"].each do |bad|
      e = assert_status(S::E_INVALID_ARGUMENT) { a.recv(timeout_ms: bad) }
      assert_includes e.detail, "timeout_ms"
      assert_status(S::E_INVALID_ARGUMENT) { a.ping(a.endpoint, timeout_ms: bad) }
      assert_status(S::E_INVALID_ARGUMENT) { a.send(a.endpoint, "x", timeout_ms: bad) }
      assert_status(S::E_INVALID_ARGUMENT) do
        runtime.call(env!(self, "POLYCALL_TEST_RPC_ENDPOINT"), "debug", "echo", nil, timeout_ms: bad)
      end
    end
    # the core's own limit for polycall_call is 1..600000
    ep = env!(self, "POLYCALL_TEST_RPC_ENDPOINT")
    assert_equal '{"echo":1}', runtime.call(ep, "debug", "echo", "1", timeout_ms: 600_000)
    assert_status(S::E_INVALID_ARGUMENT) { runtime.call(ep, "debug", "echo", "1", timeout_ms: 600_001) }
    # 0 polls, PC::WAIT_FOREVER (UINT32_MAX) is the largest accepted value
    assert_status(S::E_TIMEOUT) { a.recv(timeout_ms: 0) }
    assert a.ping(a.endpoint, timeout_ms: PC::WAIT_FOREVER)
  end

  def test_receive_capacity_bounds
    a = node("alpha")
    b = node("beta")
    [-1, -(2**40), 1.5, nil, "4"].each do |bad|
      e = assert_status(S::E_INVALID_ARGUMENT) { b.recv(timeout_ms: 0, capacity: bad) }
      assert_includes e.detail, "capacity"
    end
    a.send(b.endpoint, "12345", message_id: "cap-1")
    e = assert_status(S::E_TOO_LARGE) { b.recv(timeout_ms: 2000, capacity: 0) }
    assert_equal "5", e.output
    e = assert_status(S::E_TOO_LARGE) { b.recv(timeout_ms: 0, capacity: 4) }
    assert_equal "5", e.output
    m = b.recv(timeout_ms: 0, capacity: 5)
    assert_equal "12345", m.payload
    # capacities above the 1 MiB message limit are clamped, not allocated
    max = "\xA5".b * PC::PEER_MAX_PAYLOAD
    a.send(b.endpoint, max, message_id: "cap-2", timeout_ms: 10_000)
    assert_equal max, b.recv(timeout_ms: 5000, capacity: 2**40).payload
    a.send(b.endpoint, max, message_id: "cap-3", timeout_ms: 10_000)
    e = assert_status(S::E_TOO_LARGE) { b.recv(timeout_ms: 5000, capacity: PC::PEER_MAX_PAYLOAD - 1) }
    assert_equal PC::PEER_MAX_PAYLOAD.to_s, e.output
    assert_equal max, b.recv(timeout_ms: 0, capacity: PC::PEER_MAX_PAYLOAD).payload
  end

  def test_handles_outside_int32_are_invalid_handles
    [2**31, -(2**31) - 1, 2**63].each do |bad|
      assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(runtime, bad) }
    end
    assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(runtime, -(2**31)).endpoint }
  end

  def test_non_ascii_config_path
    dir = File.join(env!(self, "POLYCALL_TEST_TMP"), "配置 é ü – Ω")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "ruby-polycallrc-ñ")
    File.write(path, "log_level=info\nmax_connections=8\ntls_enabled=false\n")
    assert_equal S::OK, runtime.run_config(path)
    assert_equal S::OK, runtime.run_config(path, strict: false)
    assert_includes runtime.describe(path), "max_connections"
    bad = File.join(dir, "bad-ü")
    File.write(bad, "max_connections=many\n")
    e = assert_status(S::E_CONFIG) { runtime.run_config!(bad) }
    assert_includes e.detail, "max_connections"
    assert_equal S::E_NOT_FOUND, runtime.run_config(File.join(dir, "missing-ñ"))
  end

  def ruby_child(env, code)
    out, err, st = Open3.capture3(env, RbConfig.ruby, "-e", code)
    [st.exitstatus, out + err]
  end

  def test_platform_library_name_through_the_loader_search_path
    lib_dir = File.dirname(File.realpath(env!(self, "POLYCALL_LIBRARY")))
    probe = 'require "obinexus/polycall"; rt = OBINexus::Polycall::Runtime.new; ' \
            'puts [rt.library_path, rt.abi_version].join(" ")'
    code, out = ruby_child({ "POLYCALL_LIBRARY" => nil, "LD_LIBRARY_PATH" => lib_dir }, probe)
    assert_equal 0, code, out
    assert_equal "libpolycall.so.1 1", out.strip
    missing = 'require "obinexus/polycall"; begin; OBINexus::Polycall::Runtime.new; ' \
              'rescue OBINexus::Polycall::LibraryError => e; puts "#{e.status} #{e.message}"; exit 3; end'
    code, out = ruby_child({ "POLYCALL_LIBRARY" => nil, "LD_LIBRARY_PATH" => "/nonexistent" }, missing)
    assert_equal 3, code, out
    assert_match(/\A-7 libpolycall not found; set POLYCALL_LIBRARY/, out)
    assert_includes out, "libpolycall.so.1"
  end

  # Fiddle calls rb_thread_call_without_gvl unless need_gvl: true, so a
  # recv/call blocked in the core lets other Ruby threads run.
  def test_a_blocked_recv_does_not_freeze_other_ruby_threads
    b = node("beta")
    ticks = 0
    ticker = Thread.new do
      loop do
        ticks += 1
        sleep 0.005
      end
    end
    sleep 0.05
    before = ticks
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 1000) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    during = ticks - before
    assert_operator elapsed, :>=, 0.9
    assert_operator during, :>=, 50, "another Ruby thread ran #{during} times during a 1 s blocking recv"

    before = ticks
    ep = env!(self, "POLYCALL_TEST_RPC_ENDPOINT")
    runtime.call(ep, "debug", "sleep", '{"ms":500}', timeout_ms: 5000)
    assert_operator ticks - before, :>=, 25, "another Ruby thread ran during a 500 ms blocking call"
  ensure
    ticker&.kill
  end

  def test_an_infinite_recv_in_one_thread_with_cancel_from_another
    b = node("beta")
    progress = Queue.new
    waiter = Thread.new do
      b.recv(timeout_ms: PC::WAIT_FOREVER)
    rescue PC::Error => e
      e
    end
    worker = Thread.new { 20.times { |i| progress << i; sleep 0.01 } }
    assert worker.join(5), "a third thread made progress while recv blocked forever"
    assert_equal 20, progress.size
    assert waiter.alive?
    b.cancel
    assert waiter.join(5)
    assert_equal S::E_CANCELLED, waiter.value.status
  end
end
