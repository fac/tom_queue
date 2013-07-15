require 'tom_queue/helper'

describe TomQueue::Work do

  let(:work) { TomQueue::Work.new('payload') }

  it "should expose the payload" do
    work.payload.should == 'payload'
  end

end
