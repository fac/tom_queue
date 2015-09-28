require_relative "../lib/tom_queue.rb"

TomQueue.logger = Logger.new(STDOUT)
conn = Bunny.new
TomQueue.bunny = conn.start

deferred_manager = TomQueue::DeferredWorkManager.new("fa-dev")
deferred_manager.start

trap("SIGINT") { deferred_manager.stop; exit }
