
require 'net/http'
require 'tom_queue/helper'

describe TomQueue::QueueManager, "simple publish / pop" do

  let(:manager) { TomQueue::QueueManager.new('fa.test', 'manager') }
  let(:consumer) { TomQueue::QueueManager.new(manager.prefix, 'consumer1') }
  let(:consumer2) { TomQueue::QueueManager.new(manager.prefix, 'consumer2') }

  before do
    TomQueue::DeferredWorkManager.instance('fa.test').purge!

    manager.purge!
    consumer.purge!
    consumer2.purge!
  end

  it "should pop a previously published message" do
    manager.publish('some work')
    manager.pop.payload.should == 'some work'
  end

  it "should block on #pop until work is published" do
    Thread.new do
      sleep 0.1
      manager.publish('some work')
    end

    consumer.pop.payload.should == 'some work'
  end

  it "should work between objects (hello, rabbitmq)" do
    manager.publish "work"
    consumer.pop.payload.should == "work"
  end

  it "should load-balance work between multiple consumers" do
    manager.publish "foo"
    manager.publish "bar"

    consumer.pop.payload.should == "foo"
    consumer2.pop.payload.should == "bar"
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
    output.should == input
  end

  xit "should deal with the connection going away" do
    p consumer.queue.status
    manager.publish("1")
    manager.publish("2")
    manager.publish("3")

    consumer.pop.ack!.payload.should == "1"
    work2 = consumer.pop
    work2.payload.should == "2"

    # NOW WE KILL ALL THE THINGS!
    uri = URI("http://127.0.0.1:15672/api/connections")
    req = Net::HTTP::Get.new(uri.path)
    req.basic_auth('guest', 'guest')

    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end
    JSON.load(res.body).each do |connection|
      if connection['client_properties']["product"] == "Bunny"
        puts "Bye bye #{connection['name']}"
        req = Net::HTTP::Delete.new("/api/connections/#{CGI.escape(connection['name'])}")
        req.basic_auth('guest', 'guest')

        res = Net::HTTP.start(uri.hostname, uri.port) do |http|
          http.request(req)
        end
        p res
      end
    end
    
    
    # first, make sure that 2 got re-delivered!
    w = consumer.pop
    w.payload.should == "2"    
  end

  it "should not drop messages when two different priorities arrive" do
    manager.publish("1", :priority => TomQueue::BULK_PRIORITY)
    manager.publish("2", :priority => TomQueue::NORMAL_PRIORITY)
    manager.publish("3", :priority => TomQueue::HIGH_PRIORITY)
    out = []
    out << consumer.pop.ack!.payload
    out << consumer.pop.ack!.payload
    out << consumer.pop.ack!.payload
    out.sort.should == ["1", "2", "3"]
  end

  it "should handle priority queueing, maintaining per-priority FIFO ordering" do
    manager.publish("1", :priority => TomQueue::BULK_PRIORITY) 
    manager.publish("2", :priority => TomQueue::NORMAL_PRIORITY)
    manager.publish("3", :priority => TomQueue::HIGH_PRIORITY)

    # 1,2,3 in the queue - 3 wins as it's highest priority
    consumer.pop.ack!.payload.should == "3"

    manager.publish("4", :priority => TomQueue::NORMAL_PRIORITY)

    # 1,2,4 in the queue - 2 wins as it's highest (NORMAL) and first in    
    consumer.pop.ack!.payload.should == "2"
    
    manager.publish("5", :priority => TomQueue::BULK_PRIORITY)

    # 1,4,5 in the queue - we'd expect 4 (highest), 1 (first bulk), 5 (second bulk)
    consumer.pop.ack!.payload.should == "4"
    consumer.pop.ack!.payload.should == "1"
    consumer.pop.ack!.payload.should == "5"
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

    order.should == ["2","3","4","1","5"]
  end

  it "should immediately run a high priority task, when there are lots of bulks" do
    100.times do |i|
      manager.publish("stuff #{i}", :priority => TomQueue::BULK_PRIORITY)
    end

    consumer.pop.ack!.payload.should == "stuff 0"
    consumer2.pop.ack!.payload.should == "stuff 1"
    consumer.pop.payload.should == "stuff 2"

    manager.publish("HIGH1", :priority => TomQueue::HIGH_PRIORITY)
    manager.publish("NORMAL1", :priority => TomQueue::NORMAL_PRIORITY)
    manager.publish("HIGH2", :priority => TomQueue::HIGH_PRIORITY)
    manager.publish("NORMAL2", :priority => TomQueue::NORMAL_PRIORITY)

    consumer.pop.ack!.payload.should == "HIGH1"
    consumer.pop.ack!.payload.should == "HIGH2"
    consumer2.pop.ack!.payload.should == "NORMAL1"
    consumer.pop.ack!.payload.should == "NORMAL2"

    consumer2.pop.ack!.payload.should == "stuff 3"
  end

  it "should allow a message to be deferred for future execution" do
    execution_time = Time.now + 0.2
    manager.publish("future-work", :run_at => execution_time )

    consumer.pop.ack!
    Time.now.to_f.should > execution_time.to_f
  end

  describe "slow tests", :timeout => 100 do

    it "should work with lots of messages, without dropping and deliver FIFO" do
      @source_order = []
      @sink_order = []
      @mutex = Mutex.new

      # Run both consumers, in parallel threads, so in some cases, 
      # there should be a thread waiting for work
      @threads = 10.times.collect do |i|
        Thread.new do
          loop do
            thread_consumer = TomQueue::QueueManager.new(manager.prefix)

            work = thread_consumer.pop

            Thread.exit if work.payload == "the_end"            


            @mutex.synchronize do
              @sink_order << work.payload
            end

            sleep 0.5  # simulate /actual work/ by sleeping.
            work.ack!
          end
        end
      end 

      # Now publish some work
      50.times do |i|
        work = "work #{i}"
        @source_order << work
        manager.publish(work)
      end
        
      # Now publish a bunch of messages to cause the threads to exit the loop
      @threads.size.times { manager.publish "the_end" }

      # Wait for the workers to finish
      @threads.each {|t| t.join}

      # Compare what the publisher did to what the workers did.
      @source_order.should == @sink_order
    end

    it "should be able to drain the queue, block and resume when new work arrives" do
      @source_order = []
      @sink_order = []
      @mutex = Mutex.new

      # Run both consumers, in parallel threads, so in some cases, 
      # there should be a thread waiting for work
      @threads = 10.times.collect do |i|
        Thread.new do
          loop do
            thread_consumer = TomQueue::QueueManager.new(manager.prefix)

            work = thread_consumer.pop

            Thread.exit if work.payload == "the_end"            

            @mutex.synchronize do
              @sink_order << work.payload
            end

            sleep 0.5  # simulate /actual work/ by sleeping.
            work.ack!
          end
        end
      end 

      # This sleep gives the workers enough time to block on the first call to pop
      sleep 0.1 until manager.queues[TomQueue::NORMAL_PRIORITY].status[:consumer_count] == @threads.size

      # Now publish some work
      50.times do |i|
        work = "work #{i}"
        @source_order << work
        manager.publish(work)
      end

      # Rough and ready - wait for the queue to empty
      sleep 0.1 until manager.queues[TomQueue::NORMAL_PRIORITY].status[:message_count] == 0

      # Now publish some more work
      50.times do |i|
        work = "work #{i}"
        @source_order << work
        manager.publish(work)
      end

      # Now publish a bunch of messages to cause the threads to exit the loop
      @threads.size.times { manager.publish "the_end" }

      # Wait for the workers to finish
      @threads.each {|t| t.join }

      # Compare what the publisher did to what the workers did.
      @source_order.should == @sink_order
    end

    it "should work with lots of deferred work on the queue, and still schedule all messages" do
      sink = []
      sink_mutex = Mutex.new

      # sit in a loop to pop it all off again
      consumers = 5.times.collect do |i|
        Thread.new do 
          consumer = TomQueue::QueueManager.new(manager.prefix, "thread-#{i}")
          loop do
            begin
              work = consumer.pop
              Thread.exit if work.payload == "done"

              payload = JSON.load(work.payload)
              
              size = sink_mutex.synchronize do
                sink << Time.now - Time.at(payload['run_at'])
                sink.size
              end

              work.ack!
            rescue
              p $!
            end
          end
        end
      end

      # Generate some work
      max_run_at = Time.now
      200.times do |i| 
        run_at = Time.now + (rand * 6.0)
        max_run_at = [max_run_at, run_at].max
        manager.publish(JSON.dump({:id => i, :run_at => run_at.to_f}), :run_at => run_at)
      end

      consumers.size.times do
        manager.publish("done", :run_at => max_run_at + 1.0)
      end

      consumers.each { |t| t.join }

      # Sink contains the difference between the run-at time and the 
      # actual time the job was run!
      sink.each do |delta|
        # if the delta is < 0, the job was TOO EARLY! This is bad
        delta.should_not < 0
        # make sure it wasn't more than a second late!
        delta.should_not > 1
      end
    end
  end

end