require 'helper'
require 'bunny'
require 'tom_queue'
# Install a simple exception reporter that just makes noise!
TomQueue.exception_reporter = Class.new do
  def notify(exception)
    puts "Exception reported: #{exception.inspect}"
    puts exception.backtrace.join("\n")
  end
end.new

RSpec.configure do |r|

  # Make sure all tests see the same Bunny instance
  r.around do |test|
    bunny = Bunny.new(:host => "localhost")
    bunny.start
      
    TomQueue.bunny = bunny
    test.call

    begin
      bunny.close      
    rescue
      puts "Failed to close bunny: #{$!.inspect}"
    ensure
      TomQueue.bunny = nil
    end
  end

  # All tests should take < 2 seconds !!
  r.around do |test|
    timeout = self.class.metadata[:timeout] || 2
    if timeout == false
      test.call
    else
      Timeout.timeout(timeout) { test.call }
    end
  end

  r.around do |test|
    begin
      TomQueue::DeferredWorkManager.reset!

      test.call

    ensure
      # Tidy up any deferred work managers!
      TomQueue::DeferredWorkManager.instances.each_pair do |prefix, i|
        i.ensure_stopped
        i.purge!
      end
      TomQueue::DeferredWorkManager.reset!
    end
  end

end
