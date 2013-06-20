require 'helper'
require 'bunny'

BunnyInstance = Bunny.new(:host => "localhost")
BunnyInstance.start

RSpec.configure do |r|

  # Make sure all tests see the same Bunny instance
  r.before do
    TomQueue.bunny = BunnyInstance
  end

  # All tests should take < 2 seconds !!
  r.around do |test|
    Timeout.timeout(2) { test.call }
  end

end
