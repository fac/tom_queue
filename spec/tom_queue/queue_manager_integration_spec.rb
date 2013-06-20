require 'tom_queue/helper'

describe TomQueue::QueueManager, "simple publish / pop" do

  let(:manager) { TomQueue::QueueManager.new('fa.test').tap { |m| m.purge! } }

  it "should pop a previously published message" do
    manager.publish('some work')
    manager.pop.payload.should == 'some work'
  end

  it "should block on #pop until work is published" do
    Thread.new do
      sleep 0.1
      manager.publish('some work')
    end

    manager.pop.payload.should == 'some work'
  end

  it "should work between objects (hello, rabbitmq)" do
    manager2 = TomQueue::QueueManager.new("fa.test")
    manager2.publish("some work")
    manager.pop.payload.should == "some work"
  end

end