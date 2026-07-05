# frozen_string_literal: true

require_relative "../lib/obinexus/polycall"

# Compatibility alias for the repository's original top-level API.
Polycall = OBINexus::Polycall unless defined?(Polycall)
