require "spec_helper"

describe TomQueue::QueueManager do

  let(:manager) { TomQueue::QueueManager.new("test-#{Time.now.to_f}").tap(&:start_consumers!) }
  let(:channel) { TomQueue.bunny.create_channel }

  describe "basic creation" do

    it "should be a thing" do
      defined?(TomQueue::QueueManager).should be_truthy
    end

    it "should be created with a name-prefix" do
      manager.prefix.should =~ /^test-[\d.]+$/
    end

    it "should default the prefix to TomQueue.default_prefix if available" do
      TomQueue.default_prefix = "test-#{Time.now.to_f}"
      TomQueue::QueueManager.new.prefix.should == TomQueue.default_prefix
    end

    it "should raise an ArgumentError if no prefix is specified and no default is available" do
      TomQueue.default_prefix = nil
      lambda {
        TomQueue::QueueManager.new
      }.should raise_exception(ArgumentError, /prefix is required/)
    end
  end

  describe "AMQP configuration" do

    TomQueue::PRIORITIES.each do |priority|
      it "should create a queue for '#{priority}' priority" do
        manager.queues[priority].name.should == "#{manager.prefix}.balance.#{priority}"
        # Declare the queue, if the parameters don't match the brokers existing channel, then bunny will throw an
        # exception.
        channel.queue("#{manager.prefix}.balance.#{priority}", :durable => true, :auto_delete => false, :exclusive => false)
      end
    end

    it "should create a single durable topic exchange" do
      manager.exchange.name.should == "#{manager.prefix}.work"
      # Now we declare it again on the broker, which will raise an exception if the parameters don't match
      channel.topic("#{manager.prefix}.work", :durable => true, :auto_delete => false)
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

    describe "deferred execution" do

      it "should allow a run-at time to be specified" do
        manager.publish("future", :run_at => Time.now + 2.2)
      end

      it "should throw an ArgumentError exception if :run_at isn't a Time object" do
        lambda {
          manager.publish("future", :run_at => "around 10pm ?")
        }.should raise_exception(ArgumentError, /must be a Time object/)
      end

      it "should write the run_at time in the message headers as an ISO-8601 timestamp, with 4-digits of decimal precision" do
        execution_time = Time.now - 1.0
        manager.publish("future", :run_at => execution_time)
        manager.pop.ack!.headers[:headers]['run_at'].should == execution_time.iso8601(4)
      end

      it "should default to :run_at the current time" do
        manager.publish("future")
        future_time = Time.now
        Time.parse(manager.pop.ack!.headers[:headers]['run_at']).should < future_time
      end
    end

    describe "message priorities" do
      it "should have an array of priorities, in the correct order" do
        TomQueue::PRIORITIES.should be_a(Array)
        TomQueue::PRIORITIES.should == [
          TomQueue::HIGH_PRIORITY,
          TomQueue::NORMAL_PRIORITY,
          TomQueue::LOW_PRIORITY,
          TomQueue::BULK_PRIORITY
        ]
      end

      it "should allow the message priority to be set" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
      end

      it "should throw an ArgumentError if an unknown priority value is used" do
        lambda {
          manager.publish("foobar", :priority => "VERY BLOODY IMPORTANT")
        }.should raise_exception(ArgumentError, /unknown priority level/)
      end

      it "should write the priority in the message header as 'priority'" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
        manager.pop.ack!.headers[:headers]['priority'].should == TomQueue::BULK_PRIORITY
      end

      it "should default to normal priority" do
        manager.publish("foobar")
        manager.pop.ack!.headers[:headers]['priority'].should == TomQueue::NORMAL_PRIORITY
      end
    end

    TomQueue::PRIORITIES.each do |priority|
      it "should publish #{priority} priority messages to the single exchange, with routing key set to '#{priority}'" do
        manager.publish("foo", :priority => priority)
        manager.pop.ack!.response.tap do |resp|
          resp.exchange.should == "#{manager.prefix}.work"
          resp.routing_key.should == priority
        end
      end
    end

  end


  describe "QueueManager - deferred message handling" do
    describe "when publishing a deferred message" do
      it "should not publish to the normal AMQP queue" do
        manager.publish("work", :run_at => Time.now + 1)
        manager.queues.values.find { |q| channel.basic_get(q.name).first }.should be_nil
      end

      it "should call #publish_deferred" do
        run_time = Time.now + 1
        manager.should_receive(:publish_deferred).with("work", run_time, TomQueue::NORMAL_PRIORITY)
        manager.publish("work", :run_at => run_time)
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

    it "should not leave any running consumers after a subscribe timeout" do
      manager.pop.ack!
      manager.pop.ack!

      expect(manager.queues[TomQueue::LOW_PRIORITY]).to receive(:subscribe).and_raise(Timeout::Error)
      Thread.new { sleep 0.1; manager.publish("baz") }
      expect { manager.pop.ack! }.to raise_exception(Timeout::Error)
      manager.queues.values.each do |queue|
        queue.status[:consumer_count].should == 0
      end
    end

    it "should nack any messages caught before a subscribe timeout" do
      manager.pop.ack!
      manager.pop.ack!

      # Introduce a wait when subscribing to the low priority queue, which will give the normal priority
      # consumer time to catch the message
      expect(manager.queues[TomQueue::LOW_PRIORITY])
        .to receive(:subscribe).and_wrap_original { |m, *args| sleep 0.2; m.call(*args) }
      expect(manager.queues[TomQueue::BULK_PRIORITY]).to receive(:subscribe).and_raise(Timeout::Error).once
      expect(manager.channel).to receive(:nack).and_call_original

      Thread.new { sleep 0.1; manager.publish("baz") }
      expect { manager.pop.ack! }.to raise_exception(Timeout::Error)
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

  context "with a queue manager without consumers started" do
    let(:manager) { TomQueue::QueueManager.new("test-#{Time.now.to_f}") }

    it "should raise an exception when popping" do
      lambda { manager.pop }.should raise_exception(StandardError, "Cannot pop messages, consumers not started")
    end

    it "should not create any queues" do
      manager.publish("foo")

      TomQueue::PRIORITIES.each do |priority|
        queue_name = "#{manager.prefix}.balance.#{priority}"
        queue_exists?(queue_name).should == false
      end
    end

    it "should publish messages" do
      exchange = channel.topic("#{manager.prefix}.work", durable: true, auto_delete: false)
      queue = channel.queue("#{manager.prefix}.balance.#{TomQueue::NORMAL_PRIORITY}", durable: true, auto_delete: false, exclusive: false)
      queue.bind(exchange, routing_key: TomQueue::NORMAL_PRIORITY)

      manager.publish("foo")
      sleep 0.1
      queue.pop[2].should == "foo"
    end
  end
end
