require 'tom_queue/helper'

describe TomQueue, "module functions" do

  it "should store and return a shared bunny instance" do
    new_bunny = double(Bunny)
    TomQueue.bunny = new_bunny
    expect(TomQueue.bunny).to eq(new_bunny)
  end

  it "should store and return a default_prefix" do
    TomQueue.default_prefix = "foobar"
    expect(TomQueue.default_prefix).to eq("foobar")
  end
end
