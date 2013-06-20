require 'tom_queue/helper'

describe TomQueue::Work do

  let(:manager) { mock("QueueManager") }
  let(:work) { TomQueue::Work.new(manager, :response, {'headers' => true}, 'payload') }

  it "should expose the queue manager" do
    work.manager.should == manager
  end
  it "should expose the payload" do
    work.payload.should == 'payload'
  end
  it "should expose the headers" do
    work.headers.should == {'headers' => true}
  end
  it "should expose the amqp response object" do
    work.response.should == :response
  end

  describe "ack! sugar function" do
    before do
      manager.stub!(:ack => nil)
    end

    it "should call the queue_manager#ack(self)" do
      manager.should_receive(:ack)
      work.ack!
    end
    it "should return self" do
      work.ack!.should == work
    end
  end

end
