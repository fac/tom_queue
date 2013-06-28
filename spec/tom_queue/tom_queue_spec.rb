require 'tom_queue/helper'

describe TomQueue, "module functions" do

  it "should not crash if TomQueue.bunny has not been set yet" do
    # Required since our tests helpfully set TomQueue.bunny for us...
    module TomQueue
      remove_class_variable(:@@bunny)
    end
    TomQueue.bunny.should be_nil
  end

  it "should store and return a shared bunny instance" do
    new_bunny = mock(Bunny)
    TomQueue.bunny = new_bunny
    TomQueue.bunny.should == new_bunny
  end

  it "should default the default_prefix to nil" do
    TomQueue.default_prefix.should be_nil
  end
  it "should store and return a default_prefix" do
    TomQueue.default_prefix = "foobar"
    TomQueue.default_prefix.should == "foobar"
  end

end