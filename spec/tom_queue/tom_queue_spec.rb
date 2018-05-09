require 'tom_queue/helper'

describe TomQueue, "module functions" do

  it "should store and return a shared bunny instance" do
    new_bunny = double(Bunny)
    TomQueue.bunny = new_bunny
    TomQueue.bunny.should == new_bunny
  end

  it "should store and return a default_prefix" do
    TomQueue.default_prefix = "foobar"
    TomQueue.default_prefix.should == "foobar"
  end
end
