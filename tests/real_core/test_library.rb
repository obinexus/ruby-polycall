# frozen_string_literal: true

require_relative "helper"

# Loading, the installed gem, version / ABI check, status names, details.
class TestLibrary < Minitest::Test
  include RealCore

  def test_the_installed_gem_is_the_one_under_test
    gem_home = env!(self, "GEM_HOME")
    loaded = $LOADED_FEATURES.grep(%r{obinexus/polycall\.rb\z})
    refute_empty loaded
    assert loaded.all? { |f| File.expand_path(f).start_with?(File.expand_path(gem_home)) },
           "obinexus/polycall must come from the gem installed in #{gem_home}, got #{loaded}"
    refute_includes Dir.pwd, "ruby-polycall", "tests run outside the checkout"
    spec = Gem.loaded_specs.fetch("obinexus-ruby-polycall")
    assert_equal PC::VERSION, spec.version.to_s
    assert File.file?(PC::DEFAULT_CONFIG), "the gem ships ruby-polycallrc"
  end

  def test_version_and_abi_check
    rt = runtime
    assert_equal 1, rt.abi_version
    assert_equal PC::ABI_VERSION, rt.abi_version
    assert_match(/\A1\.(?:[1-9]\d*)\.\d+\z/, rt.version)
    assert_equal File.realpath(env!(self, "POLYCALL_LIBRARY")), File.realpath(rt.library_path),
                 "POLYCALL_LIBRARY is honoured first"
  end

  def test_strerror_names_every_status
    rt = runtime
    assert_equal 19, S.constants.size
    S.constants.each do |c|
      expected = c == :OK ? "POLYCALL_OK" : "POLYCALL_#{c}"
      assert rt.strerror(S.const_get(c)).start_with?("#{expected}:"), rt.strerror(S.const_get(c))
      assert_equal expected, S.name_of(S.const_get(c))
    end
    assert rt.strerror(-999).start_with?("POLYCALL_E_UNKNOWN")
  end

  def test_errors_carry_status_name_and_last_error_detail
    rt = runtime
    e = assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(rt, 987_654).endpoint }
    assert_equal "POLYCALL_E_INVALID_HANDLE", e.status_name
    assert_includes e.detail, "handle"
    assert_includes e.message, "POLYCALL_E_INVALID_HANDLE"
    assert_equal 0, rt.run_config
    assert_equal "", rt.last_error, "a successful call clears the thread's detail"
  end

  def test_last_error_is_per_thread
    rt = runtime
    assert_status(S::E_INVALID_HANDLE) { PC::Peer.from_handle(rt, 424_242).node_id }
    other = Thread.new { rt.last_error }.value
    assert_equal "", other, "another thread does not see this thread's detail"
    refute_empty rt.last_error
  end

  def test_missing_library_is_a_clear_error
    missing = File.join(env!(self, "POLYCALL_TEST_TMP"), "no-such-dir", "libpolycall.so.1")
    e = assert_raises(PC::LibraryError) { PC::Runtime.new(library_path: missing) }
    assert_equal S::E_NOT_FOUND, e.status
    assert_includes e.message, missing
  end

  def test_old_core_without_abi_v1_symbols_is_rejected
    old = env!(self, "POLYCALL_TEST_FAKE_OLD")
    e = assert_raises(PC::LibraryError) { PC::Runtime.new(library_path: old) }
    assert_equal S::E_UNSUPPORTED, e.status
    assert_includes e.message, old
    assert_includes e.message, "missing symbol polycall_ffi_abi_version"
  end

  def test_abi_version_mismatch_is_rejected
    abi2 = env!(self, "POLYCALL_TEST_FAKE_ABI2")
    e = assert_raises(PC::LibraryError) { PC::Runtime.new(library_path: abi2) }
    assert_equal S::E_UNSUPPORTED, e.status
    assert_includes e.message, "reports binding ABI 2"
  end

  def test_polycall_library_pointing_nowhere_is_a_clear_error
    saved = ENV.fetch("POLYCALL_LIBRARY", nil)
    ENV["POLYCALL_LIBRARY"] = "/nonexistent/libpolycall.so.1"
    e = assert_raises(PC::LibraryError) { PC::Runtime.new }
    assert_equal S::E_NOT_FOUND, e.status
    assert_includes e.message, "/nonexistent/libpolycall.so.1"
  ensure
    ENV["POLYCALL_LIBRARY"] = saved
  end

  def test_module_level_compatibility_api
    assert_equal 0, PC.run_config(PC::DEFAULT_CONFIG, runtime: runtime)
    assert_equal 0, PC.run_config!(PC::DEFAULT_CONFIG, runtime: runtime)
    e = assert_raises(PC::Error) { PC.run_config!("/nonexistent/ruby-polycallrc", runtime: runtime) }
    assert_equal S::E_NOT_FOUND, e.code
  end
end
