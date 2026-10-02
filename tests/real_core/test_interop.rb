# frozen_string_literal: true

require "json"
require_relative "helper"

# Cross-language interop: a Ruby peer node and a C node run by
# `polycall peer serve` / `send` / `recv` / `register` (separate processes).
class TestInterop < Minitest::Test
  include RealCore

  def teardown
    stop_cli_node(@cli_pid) if @cli_pid
    @ruby&.close unless @ruby&.closed?
  end

  def test_ruby_peer_and_cli_peer_exchange_both_ways
    token = env!(self, "POLYCALL_DEV_TOKEN")
    @cli_pid, c_ep, = start_cli_node(self, "cnode")
    @ruby = runtime.open_peer("ruby-node", token: token)
    @ruby.register("cnode", c_ep)
    assert @ruby.ping("cnode", timeout_ms: 2000)

    payload = "ruby\0to\xFFC ".b + all_bytes
    @ruby.send("cnode", payload, message_id: "ruby-to-c-1")
    rc, out, err = cli(self, "peer", "recv", "--to", c_ep, "-t", "3000")
    assert_equal 0, rc, "polycall peer recv failed: #{err}"
    msg = JSON.parse(out)
    assert_equal "ruby-node", msg["from"]
    assert_equal "ruby-to-c-1", msg["id"]
    assert_equal [payload].pack("m0"), msg["payload_b64"]

    file = File.join(env!(self, "POLYCALL_TEST_TMP"), "c-to-ruby.bin")
    back = "C\0to Ruby \u{1f30d} ".b + all_bytes.reverse
    File.binwrite(file, back)
    rc, _out, err = cli(self, "peer", "send", "--from", "cnode", "--to", @ruby.endpoint,
                        "--id", "c-to-ruby-1", "--payload-file", file)
    assert_equal 0, rc, "polycall peer send failed: #{err}"
    m = @ruby.recv(timeout_ms: 3000)
    assert_equal "cnode", m.sender
    assert_equal "c-to-ruby-1", m.message_id
    assert back == m.payload, "bytes from the C node identical in Ruby"

    @ruby.send("cnode", "again", message_id: "ruby-dup-1")
    @ruby.send("cnode", "again", message_id: "ruby-dup-1")
    rc, out, = cli(self, "peer", "recv", "--to", c_ep, "-t", "3000")
    assert_equal 0, rc
    assert_includes out, '"ruby-dup-1"'
    rc, = cli(self, "peer", "recv", "--to", c_ep, "-t", "300")
    assert_equal 6, rc, "no second copy at the C node (exit 6 = deadline)"
  end

  def test_cli_registers_on_the_ruby_node_and_reads_its_health
    @ruby = runtime.open_peer("ruby-node", token: env!(self, "POLYCALL_DEV_TOKEN"))
    rc, _out, err = cli(self, "peer", "register", "--to", @ruby.endpoint, "--id", "remote-c",
                        "--peer-endpoint", "127.0.0.1:9")
    assert_equal 0, rc, "authenticated POST /register from the CLI failed: #{err}"
    assert_equal({ "remote-c" => "127.0.0.1:9" }, @ruby.list)
    rc, out, = cli(self, "peer", "health", "--to", @ruby.endpoint)
    assert_equal 0, rc
    assert_includes out, '"node_id":"ruby-node"'
  end

  def test_call_matches_the_cli_client
    ep = env!(self, "POLYCALL_TEST_RPC_ENDPOINT")
    rc, out, = cli(self, "call", "inventory", "get", "--endpoint", ep, "--input-value", '{"item_id":"gadget-c"}')
    assert_equal 0, rc
    ruby = JSON.parse(runtime.call(ep, "inventory", "get", '{"item_id":"gadget-c"}', timeout_ms: 2000))
    assert_equal JSON.parse(out)["output"], ruby
    assert_equal false, ruby["in_stock"]
  end
end
