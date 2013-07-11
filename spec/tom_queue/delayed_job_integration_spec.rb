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
      TomQueue.exception_reporter = mock("SilentExceptionReporter", :notify => nil)
      lambda {
        Delayed::Job.new.tomqueue_publish
      }.should raise_exception(ArgumentError, /cannot publish an unsaved Delayed::Job/)
    end

    describe "when it is called on a saved job" do
      before do
        job # create the job first so we don't trigger the expectation twice
        Delayed::Job.tomqueue_manager.should_receive(:publish) do |payload, opts|
          @payload = payload
          @opts = opts
        end
      end

      it "should call publish on the queue manager" do
        job.tomqueue_publish
        @payload.should_not be_nil
      end

      describe "job priority" do
        before do
          TomQueue::DelayedJobHook::Job.tomqueue_priority_map[-10] = TomQueue::BULK_PRIORITY
          TomQueue::DelayedJobHook::Job.tomqueue_priority_map[10] = TomQueue::HIGH_PRIORITY
        end

        it "should map the priority of the job to the TomQueue priority" do
          new_job.priority = -10
          new_job.save
          @opts[:priority].should == TomQueue::BULK_PRIORITY
        end

        it "should default the priority to TomQueue::NORMAL_PRIORITY if the provided priority is unknown" do
          new_job.priority = 99
          new_job.save
          @opts[:priority].should == TomQueue::NORMAL_PRIORITY
        end
        xit "should log a warning if an unknown priority is specified" do
          pending("LOGGER STUFF")
        end
      end

      describe "run_at value" do
        it "should use the job's :run_at value by default" do
          job.tomqueue_publish
          @opts[:run_at].should == job.run_at
        end
        it "should use the run_at value provided if provided by the caller" do
          the_time = Time.now + 10.seconds
          job.tomqueue_publish(the_time)
          @opts[:run_at].should == the_time
        end
      end

      describe "the payload" do
        let(:decoded_payload) { JSON.load(@payload) }
        it "should contain the job id" do
          job.tomqueue_publish
          decoded_payload['delayed_job_id'].should == job.id
        end
        it "should contain the current updated_at timestamp (with second-level precision)" do
          job.tomqueue_publish
          job.reload
          decoded_payload['updated_at'].should == job.updated_at.iso8601(0)
        end
      end

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
      let(:exception) { RuntimeError.new("Bugger. Dropped the ball, sorry.") }

      before do
        TomQueue.exception_reporter = mock("SilentExceptionReporter", :notify => nil)
        Delayed::Job.tomqueue_manager.should_receive(:publish).and_raise(exception)
      end

      it "should not be raised out to the caller" do
        lambda { new_job.save }.should_not raise_exception
      end

      it "should notify the exception reporter" do
        TomQueue.exception_reporter.should_receive(:notify).with(exception)
        new_job.save
      end

      it "should do nothing if the exception reporter is nil" do
        TomQueue.exception_reporter = nil
        lambda { new_job.save }.should_not raise_exception
      end
      xit "should log an error message to the log" do
        pending("LOGGING")
      end
    end

  end

  describe "Delayed::Job.tomqueue_republish method" do

    it "should exist" do
      Delayed::Job.respond_to?(:tomqueue_republish).should be_true
    end

    it "should return nil" do
      Delayed::Job.tomqueue_republish.should be_nil
    end

    xit "should call #tomqueue_publish on all DB records" do

    end
  end

  describe "Delayed::Job#reserve - return the next job" do
    let(:job)     { Delayed::Job.create! }
    let(:worker)  { mock("Worker", :name => "Worker-Name-#{Time.now.to_f}") }
    let(:payload) { job.tomqueue_payload }
    let(:work)    { mock("Work", :payload => payload, :ack! => nil) }

    before do
      Delayed::Job.tomqueue_manager.stub!(:pop => work)
    end

    it "should call pop on the queue manager" do
      Delayed::Job.tomqueue_manager.should_receive(:pop)
      Delayed::Job.reserve(worker)
    end

    describe "signal handling" do
      it "should allow signal handlers during the pop" do
        Delayed::Worker.raise_signal_exceptions = false
        Delayed::Job.tomqueue_manager.should_receive(:pop) do
          Delayed::Worker.raise_signal_exceptions.should be_true
          work
        end
        Delayed::Job.reserve(worker)
      end

      it "should reset the signal handler var after the pop" do
        Delayed::Worker.raise_signal_exceptions = false
        Delayed::Job.reserve(worker)
        Delayed::Worker.raise_signal_exceptions.should == false
        Delayed::Worker.raise_signal_exceptions = true
        Delayed::Job.reserve(worker)
        Delayed::Worker.raise_signal_exceptions.should == true
      end
    end

    describe "when a TomQueue::Work object is returned" do
      let(:the_time) { Time.now }
      before { Delayed::Job.stub!(:db_time_now => the_time) }

      describe "for a job that is ready to run and not locked" do
        it "should return the job object" do
          Delayed::Job.reserve(worker).should == job
        end
        it "should ack the work object" do
          work.should_receive(:ack!)
          Delayed::Job.reserve(worker)
        end
        it "should lock the job" do
          Delayed::Job.reserve(worker)

          job.reload
          job.locked_at.to_i.should == the_time.to_i
          job.locked_by.should == worker.name
        end

        it "should tomqueue_publish the job after the Delayed::Worker.max_run_time, by default" do
          job
          Delayed::Job.tomqueue_manager.should_receive(:publish).with(job.tomqueue_payload, hash_including(:run_at => (the_time + Delayed::Worker.max_run_time)))
          Delayed::Job.reserve(worker)
        end

        it "should tomqueue_publish the job after the second arg if supplied" do
          job
          Delayed::Job.tomqueue_manager.should_receive(:publish).with(job.tomqueue_payload, hash_including(:run_at => (the_time + 99)))
          Delayed::Job.reserve(worker, 99)
        end

        describe "if there is an error during reserve" do
          before do
            Delayed::Job.should_receive(:db_time_now).and_raise(RuntimeError, "YAK NOT FOUND")
          end

          it "should not ack the job" do
            work.should_not_receive(:ack!)            
            Delayed::Job.reserve(worker) rescue nil
          end

          it "should let the exception fall out to the caller" do
            lambda {
              Delayed::Job.reserve(worker)
            }.should raise_exception(RuntimeError, "YAK NOT FOUND")
          end
        end

      end

      # describe "when a job is, somehow, locked by another worker" do

      #   it "should ack the message" do
      #     work.should_receive(:ack!)
      #     Delayed::Job.reserve(worker)
      #   end
      #   it "should return nil" do
      #     Delayed::Job.reserve(worker).should be_nil
      #   end
      # end

      # describe "when a job has run_at in the future"
      
      # describe "when the job has a different updated_at value"

      # # job has run_at in the past ?

      # # job has been updated since the message ?

      # # job save crashes ? - don't ack message, bail!

      # it "should return the job object" do
      #   Delayed::Job.reserve(worker).tap do |response|
      #     response.should be_a(Delayed::Job)
      #     response.id.should == job.id
      #   end
      # end

      # it "should only be locked by one worker"

      # it "should hold a pessemistic lock"
    end

  end

end
