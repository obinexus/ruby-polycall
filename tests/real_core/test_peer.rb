# frozen_string_literal: true

require_relative "helper"

# Real peer nodes in this Ruby process (Fiddle releases the GVL, so threads
# genuinely block in the core concurrently).
class TestPeer < Minitest::Test
  include RealCore

  def setup
    @open = []
  end

  def teardown
    @open.each do |peer|
      peer.close
    rescue PC::Error
      nil # closed by the test
    end
  end

  def node(id, bind: "127.0.0.1:0", token: nil)
    runtime.open_peer(id, bind: bind, token: token).tap { |p| @open << p }
  end

  def assert_message(at, from, id, payload, timeout_ms: 3000)
    m = at.recv(timeout_ms: timeout_ms)
    assert_equal from, m.sender, "sender id verified at the receiver"
    assert_equal id, m.message_id, "message id verified at the receiver"
    assert_equal Encoding::BINARY, m.payload.encoding
    assert_equal payload.b.bytesize, m.payload.bytesize
    assert payload.b == m.payload, "payload bytes identical"
    m
  end

  def test_identity_endpoint_and_send_only_node
    a = node("alpha")
    assert_operator a.handle, :>, 0
    assert_equal "alpha", a.node_id
    assert_match(/\A127\.0\.0\.1:[1-9]\d*\z/, a.endpoint)
    s = node("sender-only", bind: nil)
    assert_equal "", s.endpoint
    refute_equal a.handle, s.handle
    h = a.health
    assert_equal "alpha", h["node_id"]
    assert_equal "ok", h["status"]
  end

  def test_payloads_both_directions_with_sender_and_message_id
    a = node("alpha")
    b = node("beta")
    a.register("beta", b.endpoint)
    b.register("alpha", a.endpoint)
    a.send("beta", "hello beta", message_id: "a2b-1")
    assert_message(b, "alpha", "a2b-1", "hello beta")
    b.send("alpha", "hello alpha", message_id: "b2a-1")
    assert_message(a, "beta", "b2a-1", "hello alpha")
    assert a.ping("beta")
    assert b.ping(a.endpoint)
  end

  def test_payload_matrix
    a = node("alpha")
    b = node("beta")
    a.register("beta", b.endpoint)
    a.send("beta", "", message_id: "empty-1")
    assert_message(b, "alpha", "empty-1", "")
    utf8 = "héllo — 世界 \u{1f30d}"
    a.send("beta", utf8, message_id: "utf8-1")
    m = assert_message(b, "alpha", "utf8-1", utf8)
    assert_equal utf8, m.payload.dup.force_encoding(Encoding::UTF_8)
    binary = "#{all_bytes}\0\0tail\0".b
    a.send("beta", binary, message_id: "binary-1")
    assert_message(b, "alpha", "binary-1", binary)
    max = Random.new(7).bytes(PC::PEER_MAX_PAYLOAD)
    a.send("beta", max, message_id: "max-1", timeout_ms: 10_000)
    assert_message(b, "alpha", "max-1", max, timeout_ms: 5000)
    assert_status(S::E_TOO_LARGE) { a.send("beta", max + "x", message_id: "over-1") }
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 200) }
  end

  def test_registry_belongs_to_its_node_only
    a = node("alpha")
    b = node("beta")
    assert_equal({}, a.list)
    a.register("beta", b.endpoint)
    assert_equal({ "beta" => b.endpoint }, a.list)
    assert_equal({}, b.list, "no implicit sync to beta")
    a.send("beta", "x", message_id: "own-1")
    assert_message(b, "alpha", "own-1", "x")
    assert_equal({}, b.list, "receiving never registers the sender")
    assert_status(S::E_NOT_FOUND) { b.send("alpha", "x") }
    a.unregister("beta")
    assert_equal({}, a.list)
    assert_status(S::E_NOT_FOUND) { a.unregister("beta") }
    assert_status(S::E_INVALID_ARGUMENT) { a.register("bad id!", b.endpoint) }
  end

  def test_duplicate_message_id_is_delivered_once
    a = node("alpha")
    b = node("beta")
    a.register("beta", b.endpoint)
    a.send("beta", "once", message_id: "dup-1")
    a.send("beta", "once", message_id: "dup-1")
    assert_message(b, "alpha", "dup-1", "once")
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 300) }
    assert_equal 1, b.health["duplicates"]
  end

  def test_auth_failure_is_rejected_and_nothing_queued
    token = env!(self, "POLYCALL_DEV_TOKEN")
    b = node("beta", token: token)
    no_token = node("carol", bind: nil)
    wrong = node("mallory", bind: nil, token: "not-the-token")
    good = node("alpha", bind: nil, token: token)
    assert_status(S::E_AUTH) { no_token.send(b.endpoint, "x", message_id: "auth-1") }
    assert_status(S::E_AUTH) { wrong.send(b.endpoint, "x", message_id: "auth-2") }
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 200) }
    good.send(b.endpoint, "ok", message_id: "auth-3")
    assert_message(b, "alpha", "auth-3", "ok")
  end

  def test_send_to_a_dead_peer_is_a_transport_error
    a = node("alpha")
    d = runtime.open_peer("doomed")
    ep = d.endpoint
    d.close
    a.register("doomed", ep)
    assert_status(S::E_TRANSPORT) { a.send("doomed", "into the void", message_id: "dead-1", timeout_ms: 2000) }
    e = assert_status(S::E_TRANSPORT) { a.ping(ep, timeout_ms: 1000) }
    refute_empty e.detail
  end

  def test_receive_timeout_and_poll
    b = node("beta")
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 150) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    assert_operator elapsed, :>=, 0.1
    assert_operator elapsed, :<, 3.0
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 0) }
  end

  def test_too_small_buffer_leaves_the_message_queued
    a = node("alpha")
    b = node("beta")
    a.send(b.endpoint, "0123456789", message_id: "size-1")
    e = assert_status(S::E_TOO_LARGE) { b.recv(timeout_ms: 2000, capacity: 4) }
    assert_equal "10", e.output, "needed size reported"
    assert_message(b, "alpha", "size-1", "0123456789")
  end

  def test_cancel_wakes_a_blocked_receive
    b = node("beta")
    waiter = Thread.new do
      b.recv(timeout_ms: PC::WAIT_FOREVER)
    rescue PC::Error => e
      e
    end
    sleep 0.3
    assert waiter.alive?, "recv is blocked in the core"
    b.cancel
    assert waiter.join(5), "cancel woke the blocked receive"
    assert_equal S::E_CANCELLED, waiter.value.status
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 100) } # later calls wait normally
    a = node("alpha")
    a.send(b.endpoint, "after cancel", message_id: "post-cancel")
    assert_message(b, "alpha", "post-cancel", "after cancel")
  end

  def test_close_wakes_a_blocked_receive
    b = runtime.open_peer("beta")
    waiters = Array.new(3) do
      Thread.new do
        b.recv(timeout_ms: PC::WAIT_FOREVER)
      rescue PC::Error => e
        e
      end
    end
    sleep 0.3
    assert waiters.all?(&:alive?)
    b.close
    waiters.each { |t| assert t.join(5), "close woke every blocked receive" }
    assert_equal [S::E_CLOSED] * 3, waiters.map { |t| t.value.status }
  end

  def test_double_close_calls_after_close_and_invalid_handles
    rt = runtime
    p = rt.open_peer("closing")
    old = p.handle
    p.close
    assert p.closed?
    assert_status(S::E_INVALID_HANDLE) { p.close }
    [
      -> { p.endpoint }, -> { p.node_id }, -> { p.send("127.0.0.1:1", "x") }, -> { p.recv(timeout_ms: 0) },
      -> { p.cancel }, -> { p.list }, -> { p.health }, -> { p.register("x", "127.0.0.1:1") },
      -> { p.unregister("x") }, -> { p.ping("127.0.0.1:1") }
    ].each { |call| assert_status(S::E_INVALID_HANDLE, &call) }
    [0, -1, 999_999, 2_147_483_647].each do |bogus|
      assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(rt, bogus).ping("127.0.0.1:1") }
    end
    n = node("closing")
    refute_equal old, n.handle, "a stale handle is never reused"
    assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(rt, old).endpoint }
  end

  def test_open_peer_with_block_closes_it
    handle = runtime.open_peer("scoped") { |p| p.handle }
    assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(runtime, handle).endpoint }
  end

  def test_invalid_identifiers
    rt = runtime
    assert_status(S::E_INVALID_ARGUMENT) { rt.open_peer("bad id!") }
    assert_status(S::E_INVALID_ARGUMENT) { rt.open_peer("x" * 64) }
    a = node("alpha")
    assert_status(S::E_INVALID_ARGUMENT) { a.send(a.endpoint, "x", message_id: "bad id!") }
    assert_status(S::E_CONFIG) { rt.open_peer("public", bind: "0.0.0.0:0") }
    assert_raises(PC::Error) { a.register("nul\0id", a.endpoint) }
  end

  # 8 threads (4 sharing one node handle, 4 with their own node) send 320
  # messages -- more than the 256-message inbox -- while one thread drains.
  # E_BUSY is the documented backpressure answer; the sender retries with
  # the SAME message id, and every message must arrive exactly once.
  def test_concurrent_senders_shared_and_separate_nodes
    b = node("beta")
    shared = node("shared", bind: nil)
    per_thread = 40
    busy = Queue.new
    deliver = lambda do |from, id, payload|
      loop do
        from.send(b.endpoint, payload, message_id: id, timeout_ms: 5000)
        break
      rescue PC::Error => e
        raise unless e.status == S::E_BUSY

        busy << id
        sleep 0.01
      end
    end
    received = {}
    reader = Thread.new do
      (8 * per_thread).times do
        m = b.recv(timeout_ms: 10_000)
        received[m.message_id] = [m.sender, m.payload]
      end
    end
    threads = Array.new(4) do |t|
      Thread.new { per_thread.times { |i| deliver.call(shared, "shared-#{t}-#{i}", "s#{t}:#{i}") } }
    end
    threads += Array.new(4) do |t|
      Thread.new do
        own = runtime.open_peer("own#{t}", bind: nil)
        per_thread.times { |i| deliver.call(own, "own#{t}-#{i}", "o#{t}:#{i}") }
        own.close
      end
    end
    threads.each(&:join)
    assert reader.join(30), "reader finished"
    assert_equal 8 * per_thread, received.size, "every message arrived exactly once"
    assert_equal(4 * per_thread, received.count { |_, (sender, _)| sender == "shared" })
    assert_equal "s3:39", received.fetch("shared-3-39").last
    assert_equal "o2:7", received.fetch("own2-7").last
    assert_equal %w[own0 own1 own2 own3], received.values.map(&:first).reject { |s| s == "shared" }.uniq.sort
    assert_status(S::E_TIMEOUT) { b.recv(timeout_ms: 200) }
    warn "  [backpressure] #{busy.size} E_BUSY answers, retried with the same id" if busy.size.positive?
  end
end
