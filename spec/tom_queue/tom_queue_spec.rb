require 'tom_queue/helper'

describe TomQueue, "module functions" do

  it "should not crash if TomQueue.bunny has not been set yet" do
    # Required since our tests helpfully set TomQueue.bunny for us...
    module TomQueue
      remove_class_variable(:@@bunny)
    end
    expect(TomQueue.bunny).to be_nil
  end

  it "should store and return a shared bunny instance" do
    new_bunny = double(Bunny)
    TomQueue.bunny = new_bunny
    expect(TomQueue.bunny).to eq new_bunny
  end

  it "should default the default_prefix to nil" do
    module TomQueue
      remove_class_variable(:@@default_prefix) if defined?(@@default_prefix)
    end
    expect(TomQueue.default_prefix).to be_nil
  end
  it "should store and return a default_prefix" do
    TomQueue.default_prefix = "foobar"
    expect(TomQueue.default_prefix).to eq "foobar"
  end

end