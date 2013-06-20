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

end