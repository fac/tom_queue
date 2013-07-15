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

  describe "Delayed::Job#tomqueue_digest" do
    let(:job) { Delayed::Job.create! }

    it "should return a different value when the object is saved" do
      first_digest = job.tomqueue_digest
      job.update_attributes(:run_at => Time.now + 10.seconds)
      job.tomqueue_digest.should_not == first_digest
    end

    it "should return the same value, regardless of the time zone (regression)" do
      ActiveRecord::Base.time_zone_aware_attributes = true
      old_zone = Time.zone
      
      # Create a job in a funky arsed time zone
      Time.zone = "Hawaii"

      job = Delayed::Job.create!
      first_digest = job.tomqueue_digest

      Time.zone = "Auckland"

      job = Delayed::Job.find(job.id)
      job.tomqueue_digest.should == first_digest

      Time.zone = old_zone
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

    it "should not publish a message if the job has a non-nil failed_at" do
      # This is a ball-ache. after_commit swallows all exceptions, including the Mock::ExpectationFailed 
      # ones that would otherwise fail this spec if should_not_receive were used.
      job.stub!(:tomqueue_publish) { @called = true }
      job.update_attributes(:failed_at => Time.now)
      @called.should be_nil
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
          decoded_payload['delayed_job_updated_at'].should == job.updated_at.iso8601(0)
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
        new_job.stub!(:tomqueue_publish) { @called = true }

        Delayed::Job.transaction do
          new_job.save!
          @called.should be_nil
          new_job.rspec_reset
          new_job.should_receive(:tomqueue_publish).with(no_args)
        end
      end

      it "should be called after commit, when a record is updated" do
        job.stub!(:tomqueue_publish) { @called = true }

        Delayed::Job.transaction do
          job.run_at = Time.now + 10.seconds
          job.save!
          @called.should be_nil

          job.rspec_reset
          job.should_receive(:tomqueue_publish).with(no_args)
        end
      end

      it "should not be called when a record is destroyed" do
        job.stub!(:tomqueue_publish) { @called = true } # See first use of this for explaination
        job.destroy
        @called.should be_nil
      end

      it "should not be called by a destroy in a transaction" do
        job.stub!(:tomqueue_publish) { @called = true } # See first use of this for explaination
        Delayed::Job.transaction { job.destroy }
        @called.should be_nil
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

      it "should allow exceptions to escape the function" do
        Delayed::Job.tomqueue_manager.should_receive(:pop) do
          raise SignalException, "INT"
        end
        lambda {
          Delayed::Job.reserve(worker)
        }.should raise_exception(SignalException)
      end
    end

    describe "Job#invoke_job" do
      let(:payload) { mock("DelayedJobPayload", :perform => nil)}
      let(:job) { Delayed::Job.create!(:payload_object=>payload) }

      it "should perform the job" do
        payload.should_receive(:perform)
        job.invoke_job
      end

      it "should not have a problem if tomqueue_work is nil" do
        job.tomqueue_work = nil
        job.invoke_job
      end

      describe "if there is a tomqueue work object set on the object" do
        let(:work_object) { mock("WorkObject", :ack! => nil)}
        before { job.tomqueue_work = work_object}

        it "should call ack! on the work object after the job has been invoked" do
          payload.should_receive(:perform).ordered
          work_object.should_receive(:ack!).ordered
          job.invoke_job
        end

        it "should call ack! on the work object if an exception is raised" do
          payload.should_receive(:perform).ordered.and_raise(RuntimeError, "OMG!!!11")
          work_object.should_receive(:ack!).ordered
          lambda {
            job.invoke_job
          }.should raise_exception(RuntimeError, "OMG!!!11")
        end
      end
    end

    describe "if a nil message is popped" do
      before { Delayed::Job.tomqueue_manager.stub!(:pop=>nil) }

      it "should return nil" do
        Delayed::Job.reserve(worker).should be_nil
      end
      it "should sleep for a second to avoid potentially tight loops" do
        start_time = Time.now
        Delayed::Job.reserve(worker).should be_nil
        (Time.now - start_time).should > 1.0
      end
    end

    describe "when a TomQueue::Work object is returned" do

      let(:the_time) { Time.now }
      before { Delayed::Job.stub!(:db_time_now => the_time) }

      describe "for a job that is ready to run and not locked" do
        it "should return the job object" do
          Delayed::Job.reserve(worker).should == job
        end

        it "should not ack the work object" do
          work.should_not_receive(:ack!)
          Delayed::Job.reserve(worker)
        end

        it "should assign the work object to the delayed job" do
          Delayed::Job.reserve(worker).tomqueue_work.should == work
        end

        it "should lock the job" do
          Delayed::Job.reserve(worker)

          job.reload
          job.locked_at.to_i.should == the_time.to_i
          job.locked_by.should == worker.name
        end

        it "should not trigger the tomqueue_publish callback when locking the job" do
          @publish_called = false
          Delayed::Job.tomqueue_manager.stub!(:publish) { @publish_called = true }
          Delayed::Job.reserve(worker)
          @publish_called.should be_false
        end

        it "should leave the job object such that future .save! trigger the tomqueue_publish" do
          job = Delayed::Job.reserve(worker)

          @called = false
          Delayed::Job.tomqueue_manager.stub!(:publish) { @called = true }
          job.touch(:updated_at)
          job.save!
          @called.should be_true
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

      describe "if the job has been updated since the message" do
        before do
          job.update_attributes!(:run_at => Time.now + 5)
        end
        it "should ack the message" do
          work.should_receive(:ack!)
          Delayed::Job.reserve(worker)
        end
        it "should return nil" do
          Delayed::Job.reserve(worker).should be_nil
        end
        it "should not have locked the job" do
          Delayed::Job.reserve(worker)
          job.reload
          job.locked_by.should be_nil
        end
      end

      describe "if the job is locked, less than max_run_time ago" do
        # This will potentially happen if a worker crashes mid-job and 
        # the broker re-delivers the original message.
        #
        # It's worth pointing out that since the original worker will have
        # locked the job, the digest will no longer match!
        #

        before do
          # First worker pops the job
          Delayed::Job.reserve(worker).should == job
          job.reload

          # Fake out the message an updated message
          work.stub!(:payload => job.tomqueue_payload)

          # Fake out "the future", but not as far as max_run_time...
          Delayed::Job.stub!(:db_time_now => job.locked_at + 10)
        end

        it "should return nil" do
          Delayed::Job.reserve(worker).should be_nil
        end

        it "should ack the message" do
          work.should_receive(:ack!)
          Delayed::Job.reserve(worker)
        end

        it "should publish a notification to arrive at locked_at + max_run_time" do
          Delayed::Job.tomqueue_manager.should_receive(:publish).with(anything(),
             hash_including(:run_at => job.locked_at + Delayed::Worker.max_run_time))
          Delayed::Job.reserve(worker)
        end
      end

      describe "if the job is locked, more than max_run_time ago" do
        # Looks like, according to DJ, this job has crashed. Boo Hoo.
        # 
        # The worker should carry on as if the job weren't locked.

        before do
          # First worker pops the job
          Delayed::Job.reserve(worker).should == job
          job.reload

          # Fake out the message an updated message
          work.stub!(:payload => job.tomqueue_payload)

          # Fake out "the future"...
          Delayed::Job.stub!(:db_time_now => job.locked_at + Delayed::Worker.max_run_time)
        end

        it "should return the job" do
          Delayed::Job.reserve(worker).should == job
        end

        it "should re-lock the job" do
          worker.stub!(:name => "new_name_#{Time.now.to_f}")
          Delayed::Job.reserve(worker)
          job.reload
          job.locked_at.should == Delayed::Job.db_time_now
          job.locked_by.should == worker.name
        end

        it "should not ack the message" do
          work.should_not_receive(:ack!)
          Delayed::Job.reserve(worker)
        end
      end

      describe "if the job doesn't exist" do
        before do
          job.destroy
        end

        it "should ack the message" do
          work.should_receive(:ack!)
          Delayed::Job.reserve(worker)
        end

        it "should return nil" do
          Delayed::Job.reserve(worker).should be_nil
        end
      end

      # describe "if the job has a run_at in the future" do
      #   # Hmm, this is a tricky one. Again this message should have been delivered
      #   # on time and any updates to the job should have invalidated the updated_at
      #   # field.
      #   #
      #   # So I think in this case we'll just presume the message is OK and chalk the
      #   # problem down to clock sync issues between the deferred worker and the 
      #   # running worker
      #   it "shoudl lock teh job" do

      #     job.locked_at
      #   end
      #   it "should return the job"
      #   it "shoudl ack the message"

      # end
      
      describe "if the job's failed_at value is non-nil" do
        before do
          job.failed_at = Time.now
          job.save
        end
        it "should return nil" do
          Delayed::Job.reserve(worker).should be_nil
        end
        it "should not lock the job" do
          Delayed::Job.reserve(worker)
          job.reload
          job.locked_by.should be_nil
        end
        it "should ack the message" do
          work.should_receive(:ack!)
          Delayed::Job.reserve(worker)
        end
      end

      describe "if someone tries to update the object after a worker has locked it" do
        # We need to be careful if someone on the console tweaks a job that has started
        # so we'll need to wrap updates with some implicit locking and alerting.

      end

    end

  end

end
