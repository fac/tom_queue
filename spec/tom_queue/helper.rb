require 'helper'
require 'bunny'

RSpec.configure do |r|
  r.before(:all) do
    TomQueue.bunny = Bunny.new(:host => "localhost")
    TomQueue.bunny.start
  end
end
