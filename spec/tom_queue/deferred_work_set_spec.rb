require 'tom_queue/helper'

describe TomQueue::DeferredWorkSet do

  it "should be creatable" do
    TomQueue::DeferredWorkSet.new.should be_a(TomQueue::DeferredWorkSet)
  end



end