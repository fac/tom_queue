require 'helper'
require 'bunny'

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
    Timeout.timeout(2) { test.call }
  end

end
