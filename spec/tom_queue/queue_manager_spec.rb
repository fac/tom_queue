require 'tom_queue/helper'

describe TomQueue::QueueManager do

  let(:manager) { TomQueue::QueueManager.new("test-#{Time.now.to_f}") }
  let(:channel) { TomQueue.bunny.create_channel }

  describe "basic creation" do

    it "should be a thing" do
      expect(defined?(TomQueue::QueueManager)).to be_truthy
    end

    it "should be created with a name-prefix" do
      expect(manager.prefix).to be =~ /^test-[\d.]+$/
    end

    it "should default the prefix to TomQueue.default_prefix if available" do
      TomQueue.default_prefix = "test-#{Time.now.to_f}"
      expect(TomQueue::QueueManager.new.prefix).to eq TomQueue.default_prefix
    end

    it "should raise an ArgumentError if no prefix is specified and no default is available" do
      TomQueue.default_prefix = nil
      expect {
        TomQueue::QueueManager.new
      }.to raise_exception(ArgumentError, /prefix is required/)
    end

    it "should use the TomQueue.bunny object" do
      expect(manager.bunny).to eq TomQueue.bunny
    end

    it "should stick to the same bunny object, even if TomQueue.bunny changes" do
      manager
      TomQueue.bunny = "A FAKE RABBIT"
      expect(manager.bunny).to be_a(Bunny::Session)
    end
  end

  describe "AMQP configuration" do

    TomQueue::QueueManager.priorities.each do |priority|
      it "should create a queue for '#{priority}' priority" do
        expect(manager.queue(priority).name).to eq "#{manager.prefix}.balance.#{priority}"
        # Declare the queue, if the parameters don't match the brokers existing channel, then bunny will throw an
        # exception.
        channel.queue("#{manager.prefix}.balance.#{priority}", :durable => true, :auto_delete => false, :exclusive => false, :passive => true)
      end
    end

    it "should create a single durable topic exchange" do
      expect(manager.exchange.name).to eq "#{manager.prefix}.work"
      # Now we declare it again on the broker, which will raise an exception if the parameters don't match
      channel.topic("#{manager.prefix}.work", :durable => true, :auto_delete => false, :passive => true)
    end

  end

  describe "QueueManager message publishing" do

    it "should forward the payload directly" do
      manager.publish("foobar")
      expect(manager.pop.ack!.payload).to eq "foobar"
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
        expect(manager.pop.ack!.headers[:headers]['run_at']).to eq execution_time.iso8601(4)
      end

      it "should default to :run_at the current time" do
        manager.publish("future")
        future_time = Time.now
        expect(Time.parse(manager.pop.ack!.headers[:headers]['run_at'])).to be < future_time
      end
    end

    describe "message priorities" do
      it "should have an array of priorities, in the correct order" do
        expect(TomQueue::QueueManager.priorities).to be_a(Array)
        expect(TomQueue::QueueManager.priorities).to eq [
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
        expect {
          manager.publish("foobar", :priority => "VERY BLOODY IMPORTANT")
        }.to raise_exception(ArgumentError, /unknown priority level/)
      end

      it "should write the priority in the message header as 'job_priority'" do
        manager.publish("foobar", :priority => TomQueue::BULK_PRIORITY)
        expect(manager.pop.ack!.headers[:headers]['job_priority']).to eq TomQueue::BULK_PRIORITY
      end

      it "should default to normal priority" do
        manager.publish("foobar")
        expect(manager.pop.ack!.headers[:headers]['job_priority']).to eq TomQueue::NORMAL_PRIORITY
      end
    end

    TomQueue::QueueManager.priorities.each do |priority|
      it "should publish #{priority} priority messages to the single exchange, with routing key set to '#{priority}'" do
        manager.publish("foo", :priority => priority)
        manager.pop.ack!.response.tap do |resp|
          expect(resp.exchange).to eq "#{manager.prefix}.work"
          expect(resp.routing_key).to eq priority
        end
      end
    end

  end


  describe "QueueManager - deferred message handling" do
    describe "when publishing a deferred message" do
      it "should not publish to the normal AMQP queue" do
        manager.publish("work", :run_at => Time.now + 1)
        expect(manager.priorities.map { |p| p.queue }.find { |q| channel.basic_get(q.name).first }).to be_nil
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
      manager.priorities.map { |p| p.queue }.each do |queue|
        expect(queue.status[:consumer_count]).to eq 0
      end
    end

    it "should not leave any running consumers for immediate messages" do
      manager.pop.ack!
      manager.priorities.map { |p| p.queue }.each do |queue|
        expect(queue.status[:consumer_count]).to eq 0
      end
    end

    it "should not leave any running consumers after it has waited for a message " do
      manager.pop.ack!
      manager.pop.ack!
      Thread.new { sleep 0.1; manager.publish("baz") }
      manager.pop.ack!
      manager.priorities.map { |p| p.queue }.each do |queue|
        expect(queue.status[:consumer_count]).to eq 0
      end
    end

    it "should return a QueueManager::Work instance" do
      expect(manager.pop.ack!).to be_a(TomQueue::Work)
    end

    it "should return the message at the head of the queue" do
      expect(manager.pop.ack!.payload).to eq "foo"
      expect(manager.pop.ack!.payload).to eq "bar"
    end
  end

  describe "custom priorities" do
    before do
      TomQueue::QueueManager.priorities = ['foo', 'bar', 'baz']
    end

    it "should provide an accessor to return the Bunny Queue object for a given priority" do
      expect(manager.queue('foo')).to be_a(Bunny::Queue)
      expect(manager.queue('foo').name).to eq("#{manager.prefix}.balance.foo")
      expect(manager.queue('bar')).to be_a(Bunny::Queue)
      expect(manager.queue('bar').name).to eq("#{manager.prefix}.balance.bar")
    end

    describe "if the priorities change after the manager is created" do
      before do
        manager 
        TomQueue::QueueManager.priorities = ['p1', 'p2']
      end

      it "should not have queues for the new priorities" do
        expect(manager.queue('p1')).to be_nil
        expect(manager.queue('p2')).to be_nil
      end

      it "should reject messages for the new priorities" do
        expect { manager.publish("foo", :priority => 'p1') }.to raise_exception(/unknown priority level/)
      end

      it "should not have created queues for the new priorities" do
        channel.queue("#{manager.prefix}.balance.foo", :passive => true)
        expect { channel.queue("#{manager.prefix}.balance.p1", :passive => true) }.to raise_exception(Bunny::NotFound)
      end
    end

    it "should create queues for each of the priorities" do
      manager
      # Declare the queue, if the parameters don't match the brokers existing channel, then bunny will throw an
      # exception. (we use :passive so the declaration doesn't actually go an create it!)
      channel.queue("#{manager.prefix}.balance.foo", :durable => true, :auto_delete => false, :exclusive => false, :passive => true)
      channel.queue("#{manager.prefix}.balance.bar", :durable => true, :auto_delete => false, :exclusive => false, :passive => true)
    end

    it "should process jobs in the priority order specified" do
      manager.publish("foo1message", :priority => 'foo')
      manager.publish("barmessage", :priority => 'bar')
      manager.publish("foo2message", :priority => 'foo')

      expect(manager.pop.ack!.payload).to eq "foo1message"
      expect(manager.pop.ack!.payload).to eq "foo2message"
      expect(manager.pop.ack!.payload).to eq "barmessage"
    end

    it "should wait for messages from the queues if none are ready to go" do
      thread = Thread.new do
        sleep 0.01 until manager.queue('foo').consumer_count == 1
        sleep 0.01 until manager.queue('bar').consumer_count == 1
        manager.publish("foo", :priority => 'foo')

        sleep 0.01 until manager.queue('foo').consumer_count == 1
        sleep 0.01 until manager.queue('bar').consumer_count == 1
        manager.publish("bar", :priority => 'bar')
      end
      expect(manager.pop.ack!.payload).to eq "foo"
      expect(manager.pop.ack!.payload).to eq "bar"
      thread.join
    end
  end

  describe "priority_consumer_filter" do
    before do
      # Ok, let's filter out the low priority consumer
      TomQueue::QueueManager.priority_consumer_filter = lambda { |p| p.name != TomQueue::LOW_PRIORITY }
    end

    it "should create the queues even if it is filtered out (so we don't potentially drop work)" do
      channel.queue("#{manager.prefix}.balance.#{TomQueue::LOW_PRIORITY}", :durable => true, :auto_delete => false, :exclusive => false, :passive => true)
      expect(manager.queue(TomQueue::LOW_PRIORITY)).to_not be_nil
    end

    it "should not setup a consumer on the filtered queues" do
      thread = Thread.new do
        sleep 0.01 until manager.queue(TomQueue::HIGH_PRIORITY).consumer_count == 1
        consumer_count = manager.queue(TomQueue::LOW_PRIORITY).consumer_count
        manager.publish("boop", :priority => TomQueue::HIGH_PRIORITY)
        consumer_count
      end
      manager.pop.ack!
      thread.join
      expect(thread.value).to eq(0)
    end

    it "should not wait for messages from filtered priorities" do
      thread = Thread.new do
        sleep 0.01 until manager.queue(TomQueue::HIGH_PRIORITY).consumer_count == 1
        manager.publish("low", :priority => TomQueue::LOW_PRIORITY)

        sleep 0.01 until manager.queue(TomQueue::HIGH_PRIORITY).consumer_count == 1
        manager.publish("high", :priority => TomQueue::HIGH_PRIORITY)
      end
      expect(manager.pop.ack!.payload).to eq "high"
      thread.join
    end

    it "should not pop messages from filtered priorities" do
      manager.publish("low", :priority => TomQueue::LOW_PRIORITY)
      manager.publish("bulk", :priority => TomQueue::BULK_PRIORITY)
      expect(manager.pop.ack!.payload).to eq("bulk")
    end
  end

  it "should return nil work after poll_interval elapses, waiting for a message" do
    TomQueue::QueueManager.poll_interval = 0.1
    expect(Benchmark.realtime { manager.pop }).to be < 0.2
    expect(manager.pop).to be_nil
  end

end
