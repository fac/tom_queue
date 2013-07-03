require 'tom_queue/helper'

## "Integration" For lack of a better word, trying to simulate various 
# failures, such as the deferred thread shitting itself
#

describe "DeferredWorkManager integration scenarios"  do
  let(:manager) { TomQueue::DeferredWorkManager.instance('test') }
  let(:consumer) { TomQueue::QueueManager.new(manager.prefix) }

  before do 
    manager.purge!
    consumer.purge!

    consumer.publish("work1", :run_at => Time.now + 0.1)
    consumer.publish("work2", :run_at => Time.now + 0.4)

    # This will start the deferred manager, and should block
    # until the thread is actually functional
    consumer.pop.ack!.payload.should == "work1"
  end

  before do
    # Allow us to manipulate the deferred set object to induce a crash
    # Look away now...
    class TomQueue::DeferredWorkManager
      attr_reader :deferred_set
    end
    # ... and welcome back.
  end

  describe "when the thread is shutdown" do

    # This will shut the thread down with a single un-acked deferred messsage 
    before { manager.ensure_stopped }

    it "should restore un-acked messages when the thread is shutdown" do
      # we would expect the message to be on the queue again, so this
      # should "just work"
      consumer.pop.ack!.payload.should == "work2"
    end

    it "should nullify the thread" do
      manager.thread.should be_nil
    end

    it "should nullify the deferred_set" do
      manager.deferred_set.should be_nil
    end

  end
  describe "if (heaven forbid) the deferred thread were to crash" do

    before do
      # Crash the deferred thread with a YAK stampede
      manager.deferred_set.should_receive(:pop).and_raise(RuntimeError, "Yaks Everywhere!")
    end    

    let(:crash!) do
      thread = manager.thread

      # This will triggert the thread run-loop to spin once and, hopefully, crash!
      manager.deferred_set.interrupt

      # wait for the inevitable - this will not induce a crash, just wait for the thread
      # to die.
      manager.thread.join

      # Sanity check
      thread.should_not be_alive
    end

    it "should start a new deferred thread on the next pop" do
      crashed_thread = manager.thread

      crash!

      # We don't actually care if the pop works, just that the thread gets started
      Timeout.timeout(0.1) { consumer.pop.ack! } rescue nil

      manager.thread.should_not == crashed_thread
      manager.thread.should be_alive
    end

    it "should nullify the thread" do
      crash!
      manager.thread.should be_nil
    end

    it "should nullify the deferred set" do
      crash!
      manager.deferred_set.should be_nil
    end

    it "should revert un-acked messages back to the broker" do
      crash!
      consumer.pop.ack!.payload.should == "work2"
    end

    it "should notify something if the deferred thread crashes" do
      TomQueue.exception_reporter = mock("ExceptionReporter", :notify => nil)

      TomQueue.exception_reporter.should_receive(:notify) do |exception|
        exception.should be_a(RuntimeError)
        exception.message.should == "Yaks Everywhere!"
      end

      crash!
    end
    
  end

  describe "if the AMQP consumer thread crashes" do

    it "should reject the messages"

  end

end
