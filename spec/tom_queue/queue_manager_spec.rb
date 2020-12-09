require 'tom_queue/helper'

describe TomQueue::QueueManager do

  let(:manager) { TomQueue::QueueManager.new("test-#{Time.now.to_f}").tap(&:start_consumers!) }
  let(:channel) { TomQueue.bunny.create_channel }

  describe "basic creation" do

    it "should be a thing" do
      expect(defined?(TomQueue::QueueManager)).to be_truthy
    end

    it "should be created with a name-prefix" do
      expect(manager.prefix).to match(/^test-[\d.]+$/)
    end

    it "should default the prefix to TomQueue.default_prefix if available" do
      TomQueue.default_prefix = "test-#{Time.now.to_f}"
      expect(TomQueue::QueueManager.new.prefix).to eq(TomQueue.default_prefix)
    end

    it "should raise an ArgumentError if no prefix is specified and no default is available" do
      TomQueue.default_prefix = nil
      expect {
        TomQueue::QueueManager.new
      }.to raise_exception(ArgumentError, /prefix is required/)
    end
  end

  describe "AMQP configuration" do

    TomQueue::PRIORITIES.each do |priority|
      it "should create a queue for '#{priority}' priority" do
        expect(manager.queues[priority].name).to eq("#{manager.prefix}.balance.#{priority}")
        # Declare the queue, if the parameters don't match the brokers existing channel, then bunny will throw an
        # exception.
        channel.queue("#{manager.prefix}.balance.#{priority}", :durable => true, :auto_delete => false, :exclusive => false)
      end
    end

    it "should create a single durable topic exchange" do
      expect(manager.exchange.name).to eq("#{manager.prefix}.work")
      # Now we declare it again on the broker, which will raise an exception if the parameters don't match
      channel.topic("#{manager.prefix}.work", :durable => true, :auto_delete => false)
    end

  end

  describe "QueueManager message publishing" do

    it "should forward the payload directly" do
      manager.publish("foobar")
      expect(manager.pop.ack!.payload).to eq("foobar")
    end

    it "should return nil" do
      expect(manager.publish("some work")).to be_nil
    end

    it "should raise an exception if the payload isn't a string" do
      expect {
        manager.publish({"some" => {"structured_data" => true}})
      }.to raise_exception(ArgumentError, /must be a string/)
    end

    describe "deferred execution" do

      it "should allow a run-at time to be specified" do
        manager.publish("future", :run_at => Time.now + 2.2)
      end

      it "should throw an ArgumentError exception if :run_at isn't a Time object" do
        expect {
          manager.publish("future", :run_at => "around 10pm ?")
        }.to raise_exception(ArgumentError, /must be a Time object/)
      end

      it "should write the run_at time in the message headers as an ISO-8601 timestamp, with 4-digits of decimal precision" do
        execution_time = Time.now - 1.0
        manager.publish("future", :run_at => execution_time)
        expect(manager.pop.ack!.headers[:headers]['run_at']).to eq(execution_time.iso8601(4))
      end

      it "should default to :run_at the current time" do
        manager.publish("future")
        future_time = Time.now
        expect(Time.parse(manager.pop.ack!.headers[:headers]['run_at'])).to be < future_time
      end
    end

    describe "message priorities" do
      it "should have an array of priorities, in the correct order" do
        expect(TomQueue::PRIORITIES).to be_a(Array)
        expect(TomQueue::PRIORITIES).to eq([
          TomQueue::HIGH_PRIORITY,
          TomQueue::NORMAL_PRIORITY,
          TomQueue::LOW_PRIORITY,
          TomQueue::BULK_PRIORITY
        ])
      end

      it "should allow the message priority to be set" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
      end

      it "should throw an ArgumentError if an unknown priority value is used" do
        expect {
          manager.publish("foobar", :priority => "VERY BLOODY IMPORTANT")
        }.to raise_exception(ArgumentError, /unknown priority level/)
      end

      it "should write the priority in the message header as 'priority'" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
        expect(manager.pop.ack!.headers[:headers]['priority']).to eq(TomQueue::BULK_PRIORITY)
      end

      it "should default to normal priority" do
        manager.publish("foobar")
        expect(manager.pop.ack!.headers[:headers]['priority']).to eq(TomQueue::NORMAL_PRIORITY)
      end
    end

    TomQueue::PRIORITIES.each do |priority|
      it "should publish #{priority} priority messages to the single exchange, with routing key set to '#{priority}'" do
        manager.publish("foo", :priority => priority)
        manager.pop.ack!.response.tap do |resp|
          expect(resp.exchange).to eq("#{manager.prefix}.work")
          expect(resp.routing_key).to eq(priority)
        end
      end
    end

  end


  describe "QueueManager - deferred message handling" do
    describe "when publishing a deferred message" do
      it "should not publish to the normal AMQP queue" do
        manager.publish("work", :run_at => Time.now + 1)
        expect(manager.queues.values.find { |q| channel.basic_get(q.name).first }).to be_nil
      end

      it "should call #publish_deferred" do
        run_time = Time.now + 1
        expect(manager).to receive(:publish_deferred).with("work", run_time, TomQueue::NORMAL_PRIORITY)
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
        expect(queue.status[:consumer_count]).to eq(0)
      end
    end

    it "should not leave any running consumers for immediate messages" do
      manager.pop.ack!
      manager.queues.values.each do |queue|
        expect(queue.status[:consumer_count]).to eq(0)
      end
    end

    it "should not leave any running consumers after it has waited for a message " do
      manager.pop.ack!
      manager.pop.ack!
      Thread.new { sleep 0.1; manager.publish("baz") }
      manager.pop.ack!
      manager.queues.values.each do |queue|
        expect(queue.status[:consumer_count]).to eq(0)
      end
    end

    it "should not leave any running consumers after a subscribe timeout" do
      manager.pop.ack!
      manager.pop.ack!

      expect(manager.queues[TomQueue::LOW_PRIORITY]).to receive(:subscribe).and_raise(Timeout::Error)
      Thread.new { sleep 0.1; manager.publish("baz") }
      expect { manager.pop.ack! }.to raise_exception(Timeout::Error)
      manager.queues.values.each do |queue|
        expect(queue.status[:consumer_count]).to eq(0)
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
        expect(queue.status[:consumer_count]).to eq(0)
      end
    end

    it "should return a QueueManager::Work instance" do
      expect(manager.pop.ack!).to be_a(TomQueue::Work)
    end

    it "should return the message at the head of the queue" do
      expect(manager.pop.ack!.payload).to eq("foo")
      expect(manager.pop.ack!.payload).to eq("bar")
    end
  end

  context "with a queue manager without consumers started" do
    let(:manager) { TomQueue::QueueManager.new("test-#{Time.now.to_f}") }

    it "should raise an exception when popping" do
      expect { manager.pop }.to raise_exception(StandardError, "Cannot pop messages, consumers not started")
    end

    it "should not create any queues" do
      manager.publish("foo")

      TomQueue::PRIORITIES.each do |priority|
        queue_name = "#{manager.prefix}.balance.#{priority}"
        expect(queue_exists?(queue_name)).to eq(false)
      end
    end

    it "should publish messages" do
      exchange = channel.topic("#{manager.prefix}.work", durable: true, auto_delete: false)
      queue = channel.queue("#{manager.prefix}.balance.#{TomQueue::NORMAL_PRIORITY}", durable: true, auto_delete: false, exclusive: false)
      queue.bind(exchange, routing_key: TomQueue::NORMAL_PRIORITY)

      manager.publish("foo")
      sleep 0.1
      expect(queue.pop[2]).to eq("foo")
    end
  end
end
