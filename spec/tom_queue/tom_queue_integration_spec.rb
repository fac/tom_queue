require 'net/http'
require 'tom_queue/helper'

describe TomQueue::QueueManager, "simple publish / pop" do

  let(:manager) { TomQueue::QueueManager.new('fa.test') }
  let(:consumer) { TomQueue::QueueManager.new(manager.prefix) }
  let(:consumer2) { TomQueue::QueueManager.new(manager.prefix) }

  before { consumer.purge! }

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
    Time.now.should > execution_time
  end



end