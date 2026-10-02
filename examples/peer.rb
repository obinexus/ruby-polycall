# frozen_string_literal: true

# ruby -Ilib examples/peer.rb
# Two peer nodes in one process exchange a payload in each direction.
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "obinexus/polycall"

rt = OBINexus::Polycall.runtime
rt.open_peer("alpha") do |alpha|
  rt.open_peer("beta") do |beta|
    alpha.register("beta", beta.endpoint) # alpha's registry only
    alpha.send("beta", "hello\0beta", message_id: "greeting-1")
    m = beta.recv(timeout_ms: 2000)
    puts "beta got #{m.payload.bytesize} bytes from #{m.sender} (id #{m.message_id})"
    beta.send(alpha.endpoint, "hello alpha", message_id: "greeting-2")
    puts "alpha got #{alpha.recv(timeout_ms: 2000).payload.inspect}"
  end
end
