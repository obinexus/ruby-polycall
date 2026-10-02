# frozen_string_literal: true

require_relative "lib/obinexus/polycall/version"

Gem::Specification.new do |spec|
  spec.name = "obinexus-ruby-polycall"
  spec.version = OBINexus::Polycall::VERSION
  spec.authors = ["Nnamdi Michael Okpala"]
  spec.email = ["okpalan@protonmail.com"]
  spec.summary = "Ruby Fiddle binding for the Polycall binding ABI v1"
  spec.description = "Configuration validation, polycall_rpc calls and peer-to-peer nodes over " \
                     "libpolycall >= 1.1.0 (polycall.h binding ABI v1) through Ruby's Fiddle."
  spec.homepage = "https://github.com/obinexus/ruby-polycall"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "polycall_core" => "https://github.com/obinexus/polycall (>= 1.1.0, binding ABI 1)",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "examples/**/*",
    "LICENSE",
    "README.md",
    "ruby-polycallrc"
  ]
  spec.require_paths = ["lib"]

  # fiddle leaves the default gems in Ruby 3.5; declare it explicitly
  spec.add_dependency "fiddle", "~> 1.1"
  spec.add_dependency "json", "~> 2.0"
end
