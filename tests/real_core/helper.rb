# frozen_string_literal: true

# Real-core minitest helper. tests/run-real-core.sh installs the built gem
# into a clean GEM_HOME and runs these tests from outside the checkout, so
# `require "obinexus/polycall"` resolves to the INSTALLED gem.
require "minitest/autorun"
require "open3"
require "obinexus/polycall"

module RealCore
  PC = OBINexus::Polycall
  S = PC::Status

  module_function

  def runtime
    @runtime ||= PC::Runtime.new
  end

  def env!(test, name)
    value = ENV.fetch(name, "")
    test.skip("#{name} is not set (run tests/run-real-core.sh)") if value.empty?
    value
  end

  def all_bytes
    (0..255).map(&:chr).join.b
  end

  # Run the polycall CLI; returns [exit status, stdout, stderr].
  def cli(test, *args)
    out, err, st = Open3.capture3(env!(test, "POLYCALL_CLI"), *args, binmode: true)
    [st.exitstatus, out, err]
  end

  # `polycall peer serve` in its own process; returns [pid, endpoint, log].
  def start_cli_node(test, node_id)
    dir = env!(test, "POLYCALL_TEST_TMP")
    file = File.join(dir, "#{node_id}.#{Process.pid}.ep")
    log = File.join(dir, "#{node_id}.#{Process.pid}.log")
    FileUtils.rm_f(file)
    pid = Process.spawn(env!(test, "POLYCALL_CLI"), "peer", "serve", "--node-id", node_id,
                        "--endpoint", "127.0.0.1:0", "--endpoint-file", file,
                        in: File::NULL, out: log, err: log)
    100.times do
      return [pid, File.read(file).strip, log] if File.size?(file)

      sleep 0.1
    end
    Process.kill("TERM", pid)
    test.flunk("polycall peer serve did not start: #{File.read(log)}")
  end

  def stop_cli_node(pid)
    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end

module RealCoreAssertions
  def assert_status(status, &block)
    error = assert_raises(OBINexus::Polycall::Error, &block)
    assert_equal status, error.status, "unexpected status: #{error.message}"
    assert_equal status, error.code
    error
  end
end

require "fileutils"
Minitest::Test.include(RealCoreAssertions)
