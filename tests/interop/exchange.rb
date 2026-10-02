# frozen_string_literal: true

# Cross-language peer exchange (both directions) -- the Ruby side of the
# contract shared with php-polycall's tests/interop/exchange.php:
#
#   ruby tests/interop/exchange.rb serve|initiate SELF_ID PEER_ID RENDEZVOUS_DIR
#
# Opens a real peer node (127.0.0.1:0, POLYCALL_DEV_TOKEN), publishes
# RENDEZVOUS_DIR/SELF_ID.ep, registers the other side; the initiator sends
# the reference payload with id SELF-to-PEER, the server verifies sender,
# id and exact bytes and replies with the reversed payload.
require "obinexus/polycall"

role, self_id, peer_id, dir = ARGV
unless %w[serve initiate].include?(role) && self_id && peer_id && dir && File.directory?(dir)
  warn "usage: exchange.rb serve|initiate SELF_ID PEER_ID RENDEZVOUS_DIR"
  exit 2
end

$failures = 0
def check(ok, what)
  puts "#{ok ? 'PASS' : 'FAIL'}  [ruby #{ARGV[1]}] #{what}"
  $failures += 1 unless ok
end

payload = "polycall interop ".b + (0..255).map(&:chr).join.b + "h\u00e9 \u2014 \u{1f30d}".b
rt = OBINexus::Polycall::Runtime.new
node = rt.open_peer(self_id, token: ENV.fetch("POLYCALL_DEV_TOKEN", ""))
File.write(File.join(dir, "#{self_id}.ep.tmp"), node.endpoint)
File.rename(File.join(dir, "#{self_id}.ep.tmp"), File.join(dir, "#{self_id}.ep"))
puts "ruby node #{self_id} listening on #{node.endpoint} (libpolycall #{rt.version}, Ruby #{RUBY_VERSION})"

peer_file = File.join(dir, "#{peer_id}.ep")
300.times { break if File.file?(peer_file); sleep 0.1 }
unless File.file?(peer_file)
  check(false, "peer #{peer_id} never published its endpoint")
  exit 1
end
node.register(peer_id, File.read(peer_file).strip)
node.ping(peer_id, timeout_ms: 5000)
check(true, "ping #{peer_id} (answers under its own node id)")

begin
  if role == "initiate"
    node.send(peer_id, payload, message_id: "#{self_id}-to-#{peer_id}", timeout_ms: 10_000)
    check(true, "sent #{payload.bytesize} bytes to #{peer_id}")
    m = node.recv(timeout_ms: 20_000)
    check(m.sender == peer_id, "reply sender is #{peer_id} (got #{m.sender})")
    check(m.message_id == "#{peer_id}-to-#{self_id}", "reply message id #{m.message_id}")
    check(m.payload == payload.reverse, "reply bytes are the exact reversed payload (#{m.payload.bytesize} bytes)")
  else
    m = node.recv(timeout_ms: 20_000)
    check(m.sender == peer_id, "sender is #{peer_id} (got #{m.sender})")
    check(m.message_id == "#{peer_id}-to-#{self_id}", "message id #{m.message_id}")
    check(m.payload == payload, "payload bytes identical (#{m.payload.bytesize} bytes, incl. NUL and UTF-8)")
    node.send(peer_id, payload.reverse, message_id: "#{self_id}-to-#{peer_id}", timeout_ms: 10_000)
    check(true, "replied to #{peer_id} (acknowledged = stored in its inbox)")
  end
rescue OBINexus::Polycall::Error => e
  check(false, "#{e.class}: #{e.message}")
end
node.close
exit($failures.zero? ? 0 : 1)
