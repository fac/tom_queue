require 'net/http'
require 'tom_queue/helper'

describe TomQueue::QueueManager, "simple publish / pop" do

  let(:manager) { TomQueue::QueueManager.new('fa.test')}
  let(:consumer) { TomQueue::QueueManager.new(manager.prefix)}

  before { consumer.purge! }

  it "should pop a previously published message" do
    manager.publish('some work')
    manager.pop.payload.should == 'some work'
  end

  xit "should block on #pop until work is published" do
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
    consumer2 = TomQueue::QueueManager.new(manager.prefix)

    manager.publish "foo"
    manager.publish "bar"

    consumer.pop.payload.should == "foo"
    consumer2.pop.payload.should == "bar"
  end

  it "should work for more than one message!" do
    consumer2 = TomQueue::QueueManager.new(manager.prefix)

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

  it "should deal with the connection going away" do
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

end