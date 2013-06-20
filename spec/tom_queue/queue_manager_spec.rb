require 'tom_queue/helper'

describe TomQueue::QueueManager do

  let(:manager) { TomQueue::QueueManager.new('fa.test').tap { |m| m.purge! } }
  let(:channel) { TomQueue.bunny.create_channel }

  before do
    TomQueue.bunny.create_channel.queue('fa.test-balance', :passive => true).delete() rescue nil
    TomQueue.bunny.create_channel.exchange('fa.test-work', :passive => true).delete() rescue nil
  end

  describe "basic creation" do
  
    it "should be a thing" do
      defined?(TomQueue::QueueManager).should be_true
    end  

    it "should be created with a name-prefix" do
      manager.prefix.should == 'fa.test'
    end

    it "should use the TomQueue.bunny object" do
      manager.bunny.should == TomQueue.bunny
    end

    it "should stick to the same bunny object, even if TomQueue.bunny changes" do
      manager
      TomQueue.bunny = "A FAKE RABBIT"
      manager.bunny.should be_a(Bunny::Session)
    end

  end


  describe "AMQP configuration" do
    it "should create a queue with the name <prefix>-balance" do
      manager.queue.name.should == channel.queue('fa.test-balance', :passive => true).name
    end

    it "should create a durable, non-auto-deleting, non-exclusive queue" do
      # this will raise an exception if any of the options don't match the queue
      channel.queue('fa.test-balance', :durable => true, :auto_delete => false, :exclusive => false)
    end

    it "should create a durable fanout exchange with the name <prefix>-work" do
      manager.exchange.name.should == channel.fanout('fa.test-work', :durable => true, :auto_delete => false).name
    end
  end

  describe "message purging #purge!" do
    before do
      manager.publish("some work")
      manager.purge!
    end

    it "should empty the work queue" do
      manager.queue.status[:message_count].should == 0
    end
  end


  describe "QueueManager message publishing" do

    let(:queue) { channel.queue('', :auto_delete => true, :exclusive => true).bind(manager.exchange) }

    # ensure the queue exists before we start pushing messages!
    before { queue }

    it "should return nil" do
      manager.publish("some work").should be_nil
    end

    it "should raise an exception if the payload isn't a string" do
      lambda {
        manager.publish({"some" => {"structured_data" => true}})
      }.should raise_exception(ArgumentError, /must be a string/)
    end

    it "should publish a message to the declared exchange" do
      manager.publish("foobar")
      queue.pop.should_not == [nil, nil, nil]
    end

    describe "work message format" do
      let(:message) { queue.pop }
      let(:headers) { message[1] }
      let(:payload) { message[2]}

      it "should forward the payload directly" do
        manager.publish("foobar")
        payload.should == "foobar"
      end
    end
  end

  describe "QueueManager#pop - work popping" do
    before do
      manager.publish("foo")
      manager.publish("bar")
    end

    it "should not have setup a consumer before the first call" do
      manager.queue.status[:consumer_count].should == 0
    end
    it "should establish an AMQP consumer on the first call" do
      manager.pop.ack!
      manager.queue.status[:consumer_count].should == 1
    end

    it "should not setup any more consumers on subsequent calls" do
      manager.pop.ack!
      manager.pop.ack!
      manager.queue.status[:consumer_count].should == 1
    end

    it "should return a QueueManager::Work instance" do
      manager.pop.ack!.should be_a(TomQueue::Work)
    end

    it "should return the message at the head of the queue" do
      manager.pop.ack!.payload.should == "foo"
      manager.pop.ack!.payload.should == "bar"
    end

    # describe "if :block => false is specified" do

    #   xit "should not block" do
    #     Timeout.timeout(0.1) do
    #       manager.pop(:block => false)
    #     end
    #   end

    #   it "should return work if it's available" do
    #     #manager.publish("some work")
    #     manager.pop(:block => false).tap do |work|
    #       work.payload.should == "foo"
    #       work.should be_a(TomQueue::Work)
    #     end
    #   end

    #   xit "should return nil if no work is available" do
    #     manager.pop(:block => false).should be_nil
    #   end
    # end

  end


end