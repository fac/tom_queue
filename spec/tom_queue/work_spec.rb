require 'tom_queue/helper'

describe TomQueue::Work do

  let(:manager) { double("QueueManager") }
  let(:work) { TomQueue::Work.new(manager, :response, {'headers' => true}, 'payload') }

  it "should expose the queue manager" do
    expect(work.manager).to eq(manager)
  end
  it "should expose the payload" do
    expect(work.payload).to eq('payload')
  end
  it "should expose the headers" do
    expect(work.headers).to eq({'headers' => true})
  end
  it "should expose the amqp response object" do
    expect(work.response).to eq(:response)
  end

  describe "ack! sugar function" do
    before do
      allow(manager).to receive(:ack).and_return(nil)
    end

    it "should call the queue_manager#ack(self)" do
      expect(manager).to receive(:ack)
      work.ack!
    end
    it "should return self" do
      expect(work.ack!).to eq(work)
    end
  end

end
