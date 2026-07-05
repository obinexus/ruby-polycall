# frozen_string_literal: true

require_relative "lib/obinexus/polycall/version"

Gem::Specification.new do |spec|
  spec.name = "obinexus-ruby-polycall"
  spec.version = OBINexus::Polycall::VERSION
  spec.authors = ["Nnamdi Michael Okpala"]
  spec.email = ["okpalan@protonmail.com"]
  spec.summary = "Ruby Fiddle binding for libpolycall"
  spec.description = "Thin Ruby adapter over the libpolycall 1.5 FFI boundary."
  spec.homepage = "https://github.com/obinexus/ruby-polycall"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir[
    "lib/**/*",
    "examples/**/*",
    "generated/**/*",
    "LICENSE",
    "README.md",
    "ruby-polycallrc"
  ]
  spec.require_paths = ["lib"]
end
