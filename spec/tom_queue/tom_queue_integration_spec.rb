
require 'net/http'
require 'tom_queue/helper'

describe TomQueue::QueueManager, "simple publish / pop" do

  let(:manager) { TomQueue::QueueManager.new(TomQueue.default_prefix).tap(&:start_consumers!) }
  let(:consumer) { TomQueue::QueueManager.new(manager.prefix).tap(&:start_consumers!) }
  let(:consumer2) { TomQueue::QueueManager.new(manager.prefix).tap(&:start_consumers!) }

  it "should pop a previously published message" do
    manager.publish('some work')
    expect(manager.pop.payload).to eq('some work')
  end

  it "should block on #pop until work is published" do
    manager

    Thread.new do
      sleep 0.1
      manager.publish('some work')
    end

    expect(consumer.pop.payload).to eq('some work')
  end

  it "should work between objects (hello, rabbitmq)" do
    manager.publish "work"
    expect(consumer.pop.payload).to eq("work")
  end

  it "should load-balance work between multiple consumers" do
    manager.publish "foo"
    manager.publish "bar"

    expect(consumer.pop.payload).to eq("foo")
    expect(consumer2.pop.payload).to eq("bar")
  end

  it "should work for more than one message!" do
    input, output = [], []
    (0..9).each do |i|
      input << i.to_s
      manager.publish i.to_s
    end

    (input.size / 2).times do
      a = consumer.pop
      b = consumer2.pop
      output << a.ack!.payload
      output << b.ack!.payload
    end
    expect(output).to eq(input)
  end

  it "should not drop messages when two different priorities arrive" do
    manager.publish("1", :priority => TomQueue::BULK_PRIORITY)
    manager.publish("2", :priority => TomQueue::NORMAL_PRIORITY)
    manager.publish("3", :priority => TomQueue::HIGH_PRIORITY)
    out = []
    out << consumer.pop.ack!.payload
    out << consumer.pop.ack!.payload
    out << consumer.pop.ack!.payload
    expect(out.sort).to eq(["1", "2", "3"])
  end

  it "should handle priority queueing, maintaining per-priority FIFO ordering" do
    manager.publish("1", :priority => TomQueue::BULK_PRIORITY)
    manager.publish("2", :priority => TomQueue::NORMAL_PRIORITY)
    manager.publish("3", :priority => TomQueue::HIGH_PRIORITY)

    # 1,2,3 in the queue - 3 wins as it's highest priority
    expect(consumer.pop.ack!.payload).to eq("3")

    manager.publish("4", :priority => TomQueue::NORMAL_PRIORITY)

    # 1,2,4 in the queue - 2 wins as it's highest (NORMAL) and first in
    expect(consumer.pop.ack!.payload).to eq("2")

    manager.publish("5", :priority => TomQueue::BULK_PRIORITY)

    # 1,4,5 in the queue - we'd expect 4 (highest), 1 (first bulk), 5 (second bulk)
    expect(consumer.pop.ack!.payload).to eq("4")
    expect(consumer.pop.ack!.payload).to eq("1")
    expect(consumer.pop.ack!.payload).to eq("5")
  end

  it "should handle priority queueing across two consumers" do
    manager.publish("1", :priority => TomQueue::BULK_PRIORITY)
    manager.publish("2", :priority => TomQueue::HIGH_PRIORITY)
    manager.publish("3", :priority => TomQueue::NORMAL_PRIORITY)


    # 1,2,3 in the queue - 3 wins as it's highest priority
    order = []
    order << consumer.pop.ack!.payload

    manager.publish("4", :priority => TomQueue::NORMAL_PRIORITY)

    # 1,2,4 in the queue - 2 wins as it's highest (NORMAL) and first in
    order << consumer.pop.ack!.payload

    manager.publish("5", :priority => TomQueue::BULK_PRIORITY)

    # 1,4,5 in the queue - we'd expect 4 (highest), 1 (first bulk), 5 (second bulk)
    order << consumer.pop.ack!.payload
    order << consumer2.pop.ack!.payload
    order << consumer.pop.ack!.payload

    expect(order).to eq(["2","3","4","1","5"])
  end

  it "should immediately run a high priority task, when there are lots of bulks" do
    100.times do |i|
      manager.publish("stuff #{i}", :priority => TomQueue::BULK_PRIORITY)
    end

    expect(consumer.pop.ack!.payload).to eq("stuff 0")
    expect(consumer2.pop.ack!.payload).to eq("stuff 1")
    expect(consumer.pop.payload).to eq("stuff 2")

    manager.publish("HIGH1", :priority => TomQueue::HIGH_PRIORITY)
    manager.publish("NORMAL1", :priority => TomQueue::NORMAL_PRIORITY)
    manager.publish("HIGH2", :priority => TomQueue::HIGH_PRIORITY)
    manager.publish("NORMAL2", :priority => TomQueue::NORMAL_PRIORITY)

    expect(consumer.pop.ack!.payload).to eq("HIGH1")
    expect(consumer.pop.ack!.payload).to eq("HIGH2")
    expect(consumer2.pop.ack!.payload).to eq("NORMAL1")
    expect(consumer.pop.ack!.payload).to eq("NORMAL2")

    expect(consumer2.pop.ack!.payload).to eq("stuff 3")
  end

  it "should allow a message to be deferred for future execution", deferred_work_manager: true do
    execution_time = Time.now + 0.2
    manager.publish("future-work", :run_at => execution_time )

    consumer.pop.ack!
    expect(Time.now.to_f).to be > execution_time.to_f
  end

  it "uses the supplied publisher for immediate publication" do
    TomQueue.publisher = MyPublisher.new
    run_at = Time.now

    manager.publish("future-work", run_at: run_at)

    expect(TomQueue.publisher.publish_args).to eq [[
      TomQueue.bunny,
      {
        exchange_type: :topic,
        exchange_name: "#{manager.prefix}.work",
        exchange_options: { durable: true, auto_delete: false},
        message_payload: "future-work",
        message_options: {
          routing_key: "normal",
          headers: { priority: "normal", run_at: run_at.iso8601(4) }
        }
      }
    ]]
  end

  it "uses the supplied publisher for future publication" do
    TomQueue.publisher = MyPublisher.new
    run_at = Time.now + 0.2

    manager.publish("future-work", run_at: run_at )

    expect(TomQueue.publisher.publish_args).to eq [[
      TomQueue.bunny,
      {
        exchange_type: :fanout,
        exchange_name: "#{manager.prefix}.work.deferred",
        exchange_options: { durable: true, auto_delete: false},
        message_payload: "future-work",
        message_options: {
          mandatory: true,
          headers: { priority: "normal", run_at: run_at.to_f }
        }
      }
    ]]
  end

  class MyPublisher
    attr_reader :publish_args

    def initialize
      @publish_args = []
    end

    def publish(*args)
      @publish_args << args
    end
  end

  describe "slow tests", :timeout => 100 do

    class QueueConsumerThread

      class WorkObject < Struct.new(:payload, :received_at, :run_at)
        def <=>(other)
          self.received_at.to_f <=> other.received_at.to_f
        end
      end

      attr_reader :work, :thread

      def initialize(manager, &work_proc)
        @manager = manager
        @work_proc = work_proc
        @work = []
      end

      def thread_main
        loop do
          begin
            work = @manager.pop
            recv_time = Time.now

            Thread.exit if work.payload == "done"

            work_obj = WorkObject.new(work.payload, recv_time, Time.parse(work.headers[:headers]['run_at']))
            @work << work_obj
            @work_proc && @work_proc.call(work_obj)

            work.ack!
          rescue
            p $!
          end
        end

      end

      def signal_shutdown(time=nil)
        time ||= Time.now
        @manager.publish("done", :run_at => time)
      end
      def start!
        @thread ||= Thread.new(&method(:thread_main))
        self
      end
    end


    it "should work with lots of messages without dropping any" do
      source_order = []

      # Run both consumers, in parallel threads, so in some cases,
      # there should be a thread waiting for work
      consumers = 16.times.collect do |i|
        consumer = TomQueue::QueueManager.new(manager.prefix).tap(&:start_consumers!)
        QueueConsumerThread.new(consumer) { |work| sleep rand(0.5) }.start!
      end

      # Now publish some work
      250.times do |i|
        work = "work #{i}"
        source_order << work
        manager.publish(work)
      end

      sleep 0.1 until manager.queues[TomQueue::NORMAL_PRIORITY].status[:message_count] == 0

      # Now publish a bunch of messages to cause the threads to exit the loop
      consumers.each { |c| c.signal_shutdown }
      consumers.each { |c| c.thread.join }

      # Merge the list of received work together sorted by received time,
      # and compare to the source list
      sink_order = consumers.map { |c| c.work }.flatten.sort.map { |a| a.payload }

      # HACK: ignore the ordering as it is flaky, given all the threading going on.
      expect(Set.new(source_order)).to eq(Set.new(sink_order))
    end

    it "should be able to drain the queue, block and resume when new work arrives" do
      source_order = []

      # Run both consumers, in parallel threads, so in some cases,
      # there should be a thread waiting for work
      consumers = 10.times.collect do |i|
        consumer = TomQueue::QueueManager.new(manager.prefix).tap(&:start_consumers!)
        QueueConsumerThread.new(consumer) { |work| sleep rand(0.5) }.start!
      end

      # This sleep gives the workers enough time to block on the first call to pop
      sleep 0.1 until manager.queues[TomQueue::NORMAL_PRIORITY].status[:consumer_count] == consumers.size

      # Now publish some work
      50.times do |i|
        work = "work #{i}"
        source_order << work
        manager.publish(work)
      end

      # Rough and ready - wait for the queue to empty
      sleep 0.1 until manager.queues[TomQueue::NORMAL_PRIORITY].status[:message_count] == 0

      # Now publish some more work
      50.times do |i|
        work = "work 2-#{i}"
        source_order << work
        manager.publish(work)
      end

      sleep 0.1 until manager.queues[TomQueue::NORMAL_PRIORITY].status[:message_count] == 0

      # Now publish a bunch of messages to cause the threads to exit the loop
      consumers.each { |c| c.signal_shutdown }
      consumers.each { |c| c.thread.join }

      # Now merge all the consumers internal work arrays into one
      # sorted by the received_at timestamps
      sink_order = consumers.map { |c| c.work }.flatten.sort.map { |a| a.payload }

      # HACK: ignore the ordering as it is flaky, given all the threading going on.
      expect(Set.new(sink_order)).to eq(Set.new(source_order))
    end

    it "should work with lots of deferred work on the queue, and still schedule all messages", deferred_work_manager: true do
      # sit in a loop to pop it all off again
      consumers = 5.times.collect do |i|
        consumer = TomQueue::QueueManager.new(manager.prefix).tap(&:start_consumers!)
        QueueConsumerThread.new(consumer).start!
      end

      # Generate some work
      max_run_at = Time.now
      200.times do |i|
        run_at = Time.now + (rand * 6.0)
        max_run_at = [max_run_at, run_at].max
        manager.publish(JSON.dump(:id => i), :run_at => run_at)
      end

      # Shutdown the consumers again
      consumers.each do |c|
        c.signal_shutdown(max_run_at + 1.0)
      end
      consumers.each { |c| c.thread.join }

      # Now make sure none of the messages were delivered too late!
      total_size = 0
      consumers.each do |c|
        total_size += c.work.size
        c.work.each do |work|
          expect(work.received_at).to be < (work.run_at + 1.0)
        end
      end

      expect(total_size).to eq(200)
    end
  end

end
