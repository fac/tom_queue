require 'helper'
require 'bunny'

TomQueue.bunny = Bunny.new(:host => "localhost")
TomQueue.bunny.start

RSpec.configure do |r|

  # All tests should take < 2 seconds !!
  r.around do |test|
    Timeout.timeout(2) { test.call }
  end

end
