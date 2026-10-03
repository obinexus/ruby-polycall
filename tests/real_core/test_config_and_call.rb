# frozen_string_literal: true

require "json"
require_relative "helper"

# polycall_ffi_run_config / describe against the real grammar.
class TestConfig < Minitest::Test
  include RealCore

  def write(name, text)
    path = File.join(env!(self, "POLYCALL_TEST_TMP"), name)
    File.write(path, text)
    path
  end

  def test_shipped_rc_files_validate_strictly
    rt = runtime
    assert_equal S::OK, rt.run_config, "the gem's ruby-polycallrc, run=1"
    assert_equal S::OK, rt.run_config!(PC::DEFAULT_CONFIG)
    example = File.join(File.dirname(PC::DEFAULT_CONFIG), "examples", "ruby-polycallrc")
    assert_equal S::OK, rt.run_config(example, strict: true)
    description = JSON.parse(rt.describe(PC::DEFAULT_CONFIG))
    assert description.key?("layer"), description.inspect
  end

  def test_missing_and_empty_paths
    rt = runtime
    assert_equal S::E_NOT_FOUND, rt.run_config(File.join(env!(self, "POLYCALL_TEST_TMP"), "missing-polycallrc"))
    assert_equal S::E_INVALID_ARGUMENT, rt.run_config("")
    e = assert_status(S::E_NOT_FOUND) { rt.run_config!("/nonexistent/ruby-polycallrc") }
    assert_equal "POLYCALL_E_NOT_FOUND", e.status_name
  end

  def test_invalid_value_is_a_config_error_naming_the_key
    rt = runtime
    bad = write("bad-polycallrc", "max_connections=lots\n")
    assert_equal S::E_CONFIG, rt.run_config(bad, strict: false)
    assert_includes rt.last_error, "max_connections"
    e = assert_status(S::E_CONFIG) { rt.run_config!(bad) }
    assert_includes e.detail, "max_connections"
  end

  def test_unknown_key_is_a_warning_unless_strict
    rt = runtime
    path = write("unknown-polycallrc", "log_level=info\nmystery_key=1\n")
    assert_equal S::OK, rt.run_config(path, strict: false)
    assert_equal S::E_CONFIG, rt.run_config(path, strict: true)
    assert_equal S::E_CONFIG, rt.run_config(path), "run_config(path) defaults to strict (run=1)"
  end

  def test_tls_is_refused_not_faked_when_strict
    rt = runtime
    path = write("tls-polycallrc", "tls_enabled=true\ncert_file=/x/c.pem\nkey_file=/x/k.pem\n")
    assert_equal S::OK, rt.run_config(path, strict: false)
    assert_equal S::E_UNSUPPORTED, rt.run_config(path, strict: true)
    assert_includes rt.last_error.downcase, "tls"
  end
end

# polycall_call against a running `polycall start` runtime.
class TestCall < Minitest::Test
  include RealCore

  def endpoint
    env!(self, "POLYCALL_TEST_RPC_ENDPOINT")
  end

  def test_success
    rt = runtime
    assert_equal '{"item_id":"widget-a","quantity":42,"in_stock":true}',
                 rt.call(endpoint, "inventory", "get", '{"item_id":"widget-a"}', timeout_ms: 2000)
    assert_equal '{"echo":null}', rt.call(endpoint, "debug", "echo", nil, timeout_ms: 2000)
    input = { "s" => "hé \u{1f30d}", "n" => [1, 2.5, nil], "t" => true }
    assert_equal({ "echo" => input },
                 JSON.parse(rt.call(endpoint, "debug", "echo", JSON.generate(input), timeout_ms: 2000)))
  end

  def test_unknown_operation
    assert_status(S::E_NOT_FOUND) { runtime.call(endpoint, "inventory", "teleport", "{}", timeout_ms: 2000) }
  end

  def test_remote_error_carries_the_error_object
    e = assert_status(S::E_REMOTE) { runtime.call(endpoint, "inventory", "get", '{"item_id":"nope"}', timeout_ms: 2000) }
    assert_includes e.output, "item.unknown"
  end

  def test_deadline_exceeded
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_status(S::E_TIMEOUT) { runtime.call(endpoint, "debug", "sleep", '{"ms":2000}', timeout_ms: 150) }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0, :<, 1.9
  end

  def test_invalid_input
    assert_status(S::E_INVALID_ARGUMENT) { runtime.call(endpoint, "debug", "echo", "{not json", timeout_ms: 1000) }
    assert_status(S::E_INVALID_ARGUMENT) { runtime.call(endpoint, "debug", "echo", "{}", timeout_ms: 0) }
    assert_status(S::E_INVALID_ARGUMENT) { runtime.call("no-port", "debug", "echo", nil, timeout_ms: 1000) }
  end

  def test_against_a_polycall_daemon
    ep = env!(self, "POLYCALL_TEST_DAEMON_ENDPOINT")
    assert_equal '{"item_id":"widget-a","quantity":42,"in_stock":true}',
                 runtime.call(ep, "inventory", "get", '{"item_id":"widget-a"}', timeout_ms: 2000)
    assert_status(S::E_NOT_FOUND) { runtime.call(ep, "inventory", "teleport", "{}", timeout_ms: 2000) }
    e = assert_status(S::E_REMOTE) { runtime.call(ep, "inventory", "get", '{"item_id":"nope"}', timeout_ms: 2000) }
    assert_includes e.output, "item.unknown"
    assert_status(S::E_TIMEOUT) { runtime.call(ep, "debug", "sleep", '{"ms":2000}', timeout_ms: 150) }
    dir = File.join(env!(self, "POLYCALL_TEST_TMP"), "daemon")
    out, st = Open3.capture2e(env!(self, "POLYCALL_CLI"), "daemon", "status", "--state-dir", File.join(dir, "state"),
                              File.join(dir, "Polycallfile"))
    assert st.success?, out
    assert_includes out, ep
  end

  def test_no_runtime
    assert_status(S::E_TRANSPORT) { runtime.call("127.0.0.1:1", "inventory", "get", "{}", timeout_ms: 1000) }
  end

  def test_concurrent_calls_from_threads
    results = Array.new(8) do |i|
      Thread.new { runtime.call(endpoint, "debug", "echo", JSON.generate({ "i" => i }), timeout_ms: 5000) }
    end.map(&:value)
    assert_equal (0...8).map { |i| { "echo" => { "i" => i } } }, results.map { |r| JSON.parse(r) }
  end
end
