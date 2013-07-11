require 'tom_queue/helper'

describe TomQueue, "once hooked" do

  before do
    TomQueue.default_prefix = "default-prefix"
    TomQueue.hook_delayed_job!
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
  end

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

  describe "Delayed::Job.tomqueue_manager" do
    it "should return a TomQueue::QueueManager instance" do
      Delayed::Job.tomqueue_manager.should be_a(TomQueue::QueueManager)
    end

    it "should have used the default prefix configured" do
      Delayed::Job.tomqueue_manager.prefix.should == "default-prefix"
    end

    it "should return the same object on subsequent calls" do
      Delayed::Job.tomqueue_manager.should == Delayed::Job.tomqueue_manager
    end

    it "should be reset by rspec (1)" do
      TomQueue.default_prefix = "foo"
      Delayed::Job.tomqueue_manager.prefix.should == "foo"
    end

    it "should be reset by rspec (1)" do
      TomQueue.default_prefix = "bar"
      Delayed::Job.tomqueue_manager.prefix.should == "bar"
    end
  end


  describe "Delayed::Job#tomqueue_publish" do
    let(:job) { Delayed::Job.create! }
    let(:new_job) { Delayed::Job.new }

    it "should exist" do
      job.respond_to?(:tomqueue_publish).should be_true
    end

    it "should return nil" do
      job.tomqueue_publish.should be_nil
    end

    it "should raise an exception if it is called on an unsaved job" do
      lambda {
        Delayed::Job.new.tomqueue_publish
      }.should raise_exception(ArgumentError, /cannot publish an unsaved Delayed::Job/)
    end

    it "should publish a message to the TomQueue queue manager" do

    end

    describe "callback triggering" do
      it "should be called after create when there is no explicit transaction" do
        new_job.should_receive(:tomqueue_publish).with(no_args)
        new_job.save!
      end

      it "should be called after update when there is no explicit transaction" do
        job.should_receive(:tomqueue_publish).with(no_args)
        job.run_at = Time.now + 10.seconds
        job.save!
      end

      it "should be called after commit, when a record is saved" do
        new_job.should_not_receive(:tomqueue_publish)

        Delayed::Job.transaction do
          new_job.save!
          new_job.rspec_reset
          new_job.should_receive(:tomqueue_publish).with(no_args)
        end
      end

      it "should be called after commit, when a record is updated" do
        job.should_not_receive(:tomqueue_publish)

        Delayed::Job.transaction do
          job.run_at = Time.now + 10.seconds
          job.save!

          job.rspec_reset
          job.should_receive(:tomqueue_publish).with(no_args)
        end
      end

      it "should not be called when a record is destroyed" do
        job.should_not_receive(:tomqueue_publish)
        job.destroy
      end

      it "should not be called by a destroy in a transaction" do
        job.should_not_receive(:tomqueue_publish)
        Delayed::Job.transaction { job.destroy }
      end
    end

    describe "if an exception is raised during the publish" do
      it "should notify the exception handler"
      it "should log an error message to the log"
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
