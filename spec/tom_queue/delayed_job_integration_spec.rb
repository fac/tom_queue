require 'tom_queue/helper'

describe TomQueue, "once hooked" do
  before { TomQueue.hook_delayed_job! }

  it "should set the Delayed::Worker sleep delay to 0" do
    # This makes sure the Delayed::Worker loop spins around on
    # an empty queue to block on TomQueue::QueueManager#pop, so
    # the job will start as soon as we receive a push from RMQ
    Delayed::Worker.sleep_delay.should == 0
  end


  describe "TomQueue::DelayedJobHook::Job" do
    it "should use the TomQueue job as the Delayed::Job" do
      Delayed::Job.should == TomQueue::DelayedJobHook::Job
    end

    it "should be a subclass of ::Delayed::Backend::ActiveRecord::Job" do
      TomQueue::DelayedJobHook::Job.superclass.should == ::Delayed::Backend::ActiveRecord::Job
    end
  end

  describe "Delayed::Job#tomqueue_publish" do
    let(:job) { Delayed::Job.create! }

    it "should exist" do
      job.respond_to?(:tomqueue_publish).should be_true
    end

    it "should raise an exception if it is called on an unsaved job"


    it "should return nil" do
      job.tomqueue_publish.should be_nil
    end
  end

  describe "Delayed::Job.tomqueue_republish method" do

    it "should exist" do
      Delayed::Job.respond_to?(:tomqueue_republish).should be_true
    end

    it "should return nil" do
      Delayed::Job.tomqueue_republish.should be_nil
    end
  end
end
