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

    TomQueue::PRIORITIES.each do |priority|
      it "should create a queue for '#{priority}' priority" do
        manager.queues[priority].name.should == "fa.test.balance.#{priority}"
        # Declare the queue, if the parameters don't match the brokers existing channel, then bunny will throw an
        # exception.
        channel.queue("fa.test.balance.#{priority}", :durable => true, :auto_delete => false, :exclusive => false)
      end

      it "should create a durable fanout exchange for '#{priority}' priority" do
        manager.exchanges[priority].name.should == "fa.test.work.#{priority}"
        # Now we declare it again on the broker, which will raise an exception if the parameters don't match
        channel.fanout("fa.test.work.#{priority}", :durable => true, :auto_delete => false)
      end
    end
  end

  describe "message purging #purge!" do
    before do
      TomQueue::PRIORITIES.each do |priority|
        manager.publish("some work", :priority => priority)
      end
      manager.purge!
    end

    TomQueue::PRIORITIES.each do |priority|
      it "should empty the '#{priority}' priority queue" do
        manager.queues[priority].status[:message_count].should == 0
      end
    end
  end

  describe "QueueManager message publishing" do

    it "should forward the payload directly" do
      manager.publish("foobar")
      manager.pop.ack!.payload.should == "foobar"
    end

    it "should return nil" do
      manager.publish("some work").should be_nil
    end

    it "should raise an exception if the payload isn't a string" do
      lambda {
        manager.publish({"some" => {"structured_data" => true}})
      }.should raise_exception(ArgumentError, /must be a string/)
    end

    describe "message priorities" do
      it "should have an array of priorities, in the correct order" do
        TomQueue::PRIORITIES.should be_a(Array)
        TomQueue::PRIORITIES.should == [
          TomQueue::HIGH_PRIORITY,
          TomQueue::NORMAL_PRIORITY,
          TomQueue::BULK_PRIORITY
        ]
      end

      it "should have ordered the array of priorities in the correct order!" do

      end
      it "should allow the message priority to be set" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
      end

      it "should throw an ArgumentError if an unknown priority value is used" do
        lambda {
          manager.publish("foobar", :priority => "VERY BLOODY IMPORTANT")
        }.should raise_exception(ArgumentError, /unknown priority level/)
      end

      it "should write the priority in the message header as 'job_priority'" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
        manager.pop.ack!.headers[:headers]['job_priority'].should == TomQueue::BULK_PRIORITY
      end

      it "should default to normal priority" do
        manager.publish("foobar")
        manager.pop.ack!.headers[:headers]['job_priority'].should == TomQueue::NORMAL_PRIORITY
      end
    end

    TomQueue::PRIORITIES.each do |priority|
      it "should publish #{priority} priority messages to the #{priority} queue" do
        manager.publish("foo", :priority => priority)
        manager.pop.ack!.response.exchange.should == "fa.test.work.#{priority}"
      end
    end

  end

  describe "QueueManager#pop - work popping" do
    before do
      manager.publish("foo")
      manager.publish("bar")
    end

    it "should not have setup a consumer before the first call" do
      manager.queues.values.each do |queue|
        queue.status[:consumer_count].should == 0
      end
    end

    it "should not leave any running consumers for immediate messages" do
      manager.pop.ack!
      manager.queues.values.each do |queue|
        queue.status[:consumer_count].should == 0
      end
    end

    it "should not leave any running consumers after it has waited for a message " do
      manager.pop.ack!
      manager.pop.ack!
      Thread.new { sleep 0.1; manager.publish("baz") }
      manager.pop.ack!
      manager.queues.values.each do |queue|
        queue.status[:consumer_count].should == 0
      end
    end

    it "should return a QueueManager::Work instance" do
      manager.pop.ack!.should be_a(TomQueue::Work)
    end

    it "should return the message at the head of the queue" do
      manager.pop.ack!.payload.should == "foo"
      manager.pop.ack!.payload.should == "bar"
    end
  end

end