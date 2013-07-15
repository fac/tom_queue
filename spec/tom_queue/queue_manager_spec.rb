require 'tom_queue/helper'

describe TomQueue::QueueManager do

  let(:manager) { TomQueue::QueueManager.new('fa.test').tap { |m| m.purge! } }

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



  describe "message purging #purge!" do
    it "should leave all queues empty" do
      manager.publish("some work")
      manager.purge!
      manager.pop(:block => false).should be_nil
    end
  end

  describe "QueueManagermessage publishing" do

    it "should return nil" do
      manager.publish("some work").should be_nil
    end

    describe "work message format" do


    end

  end

  describe "QueueManager#pop - work popping" do
    around do |test|
      Timeout.timeout(0.1) { test.call }
    end

    it "should return the message at the head of the queue" do
      manager.publish("foo")
      manager.publish("bar")
      manager.pop.payload.should == "foo"
      manager.pop.payload.should == "bar"
    end

    it "should return a QueueManager::Work instance" do
      manager.publish("foo")
      manager.pop.should be_a(TomQueue::Work)
    end


    describe "if :block => false is specified" do

      it "should not block if :block => false is specified" do
        Timeout.timeout(0.1) do
          manager.pop(:block => false)
        end
      end
      it "should return work if it's available" do
        manager.publish("some work")
        manager.pop(:block => false).tap do |work|
          work.payload.should == "some work"
          work.should be_a(TomQueue::Work)
        end
      end
      it "should return nil if no work is available" do
        manager.pop(:block => false).should be_nil
      end
    end

  end


end