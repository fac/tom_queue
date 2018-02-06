require 'tom_queue/helper'

describe TomQueue, "once hooked" do

  let(:job) { Delayed::Job.create! }
  let(:new_job) { Delayed::Job.new }


  it "should set the Delayed::Worker sleep delay to 0" do
    # This makes sure the Delayed::Worker loop spins around on
    # an empty queue to block on TomQueue::QueueManager#pop, so
    # the job will start as soon as we receive a push from RMQ
    expect(Delayed::Worker.sleep_delay).to eq(0)
  end

  describe "TomQueue::DelayedJob::Job" do
    it "should use the TomQueue job as the Delayed::Job" do
      expect(Delayed::Job).to eq(TomQueue::DelayedJob::Job)
    end

    it "should be a subclass of ::Delayed::Backend::ActiveRecord::Job" do
      expect(TomQueue::DelayedJob::Job.superclass).to eq(::Delayed::Backend::ActiveRecord::Job)
    end
  end

  describe "Delayed::Job.tomqueue_manager" do
    it "should return a TomQueue::QueueManager instance" do
      expect(Delayed::Job.tomqueue_manager).to be_a(TomQueue::QueueManager)
    end

    it "should have used the default prefix configured" do
      expect(Delayed::Job.tomqueue_manager.prefix).to eq(TomQueue.default_prefix)
    end

    it "should return the same object on subsequent calls" do
      expect(Delayed::Job.tomqueue_manager).to eq(Delayed::Job.tomqueue_manager)
    end

    it "should be reset by rspec (1)" do
      TomQueue.default_prefix = "foo"
      expect(Delayed::Job.tomqueue_manager.prefix).to eq("foo")
    end

    it "should be reset by rspec (2)" do
      TomQueue.default_prefix = "bar"
      expect(Delayed::Job.tomqueue_manager.prefix).to eq("bar")
    end
  end

  describe "Delayed::Job#tomqueue_digest" do

    it "should return a different value when the object is saved" do
      first_digest = job.tomqueue_digest
      job.update_attributes(:run_at => Time.now + 10.seconds)
      expect(job.tomqueue_digest).to_not eq(first_digest)
    end

    it "should return the same value, regardless of the time zone (regression)" do
      ActiveRecord::Base.time_zone_aware_attributes = true
      old_zone, Time.zone = Time.zone, "Hawaii"

      job = Delayed::Job.create!
      first_digest = job.tomqueue_digest

      Time.zone = "Auckland"

      job = Delayed::Job.find(job.id)
      expect(job.tomqueue_digest).to eq(first_digest)

      Time.zone = old_zone
    end
  end

  describe "Delayed::Job#tomqueue_payload" do

    let(:payload) { JSON.load(job.tomqueue_payload)}

    it "should return a hash" do
      expect(payload).to be_a(Hash)
    end

    it "should contain the job id" do
      expect(payload['delayed_job_id']).to eq(job.id)
    end

    it "should contain the current updated_at timestamp (with second-level precision)" do
      expect(payload['delayed_job_updated_at']).to eq(job.updated_at.iso8601(0))
    end

    it "should contain the digest after saving" do
      expect(payload['delayed_job_digest']).to eq(job.tomqueue_digest)
    end
  end

  describe "Delayed::Job#tomqueue_publish" do

    it "should return nil" do
      expect(job.tomqueue_publish).to be_nil
    end

    it "should raise an exception if it is called on an unsaved job" do
      TomQueue.exception_reporter = double("SilentExceptionReporter", :notify => nil)
      expect {
        Delayed::Job.new.tomqueue_publish
      }.to raise_exception(ArgumentError, /cannot publish an unsaved Delayed::Job/)
    end

    describe "when it is called on a persisted job" do

      before do
        job # create the job first so we don't trigger the expectation twice

        @called = false
        allow(Delayed::Job.tomqueue_manager).to receive(:publish) do |payload, opts|
          @called = true
          @payload = payload
          @opts = opts
        end
      end

      it "should call publish on the queue manager" do
        job.tomqueue_publish
        expect(@called).to be_truthy
      end

      describe "job priority" do
        before do
          TomQueue::DelayedJob.priority_map[-10] = TomQueue::BULK_PRIORITY
          TomQueue::DelayedJob.priority_map[10]  = TomQueue::HIGH_PRIORITY
        end

        it "should map the priority of the job to the TomQueue priority" do
          new_job.priority = -10
          new_job.save
          expect(@opts[:priority]).to eq(TomQueue::BULK_PRIORITY)
        end

        describe "if an unknown priority value is used" do
          before do
            new_job.priority = 99
          end

          it "should default the priority to TomQueue::NORMAL_PRIORITY" do
            new_job.save
            expect(@opts[:priority]).to eq(TomQueue::NORMAL_PRIORITY)
          end

          it "should log a warning" do
            allow(TomQueue.logger).to receive(:warn)
            new_job.save
          end
        end
      end

      describe "run_at value" do

        it "should use the job's :run_at value by default" do
          job.tomqueue_publish
          expect(@opts[:run_at]).to eq(job.run_at)
        end

        it "should use the run_at value provided if provided by the caller" do
          the_time = Time.now + 10.seconds
          job.tomqueue_publish(the_time)
          expect(@opts[:run_at]).to eq(the_time)
        end

      end

      describe "the payload" do

        before { allow(job).to receive(:tomqueue_payload).and_return("PAYLOAD") }

        it "should be the return value from #tomqueue_payload" do
          job.tomqueue_publish
          expect(@payload).to eq("PAYLOAD")
        end
      end
    end

    describe "if an exception is raised during the publish" do
      let(:exception) { RuntimeError.new("Bugger. Dropped the ball, sorry.") }

      before do
        TomQueue.exception_reporter = double("SilentExceptionReporter", :notify => nil)
        allow(Delayed::Job.tomqueue_manager).to receive(:publish).and_raise(exception)
      end

      it "should not be raised out to the caller" do
        expect { new_job.save }.to_not raise_exception
      end

      it "should notify the exception reporter" do
        expect(TomQueue.exception_reporter).to receive(:notify).with(exception)
        new_job.save
      end

      it "should do nothing if the exception reporter is nil" do
        TomQueue.exception_reporter = nil
        expect { new_job.save }.to_not raise_exception
      end

      it "should log an error message to the log" do
        expect(TomQueue.logger).to receive(:error)
        new_job.save
      end
    end
  end

  describe "publish callbacks in Job lifecycle" do

    it "should allow Mock::ExpectationFailed exceptions to escape the callback" do
      TomQueue.logger = Logger.new("/dev/null")
      TomQueue.exception_reporter = nil
      allow(Delayed::Job.tomqueue_manager).to receive(:publish).with("spurious arguments").once
      expect {
        job.update_attributes(:run_at => Time.now + 5.seconds)
      }.to raise_exception(RSpec::Mocks::MockExpectationError)

      Delayed::Job.tomqueue_manager.publish("spurious arguments") # do this, otherwise it will fail
    end

    it "should not publish a message if the job has a non-nil failed_at" do
      expect(job).to_not receive(:tomqueue_publish)
      job.update_attributes(:failed_at => Time.now)
    end

    it "should be called after create when there is no explicit transaction" do
      expect(new_job).to receive(:tomqueue_publish).with(no_args)
      new_job.save!
    end

    it "should be called after update when there is no explicit transaction" do
      expect(job).to receive(:tomqueue_publish).with(no_args)
      job.run_at = Time.now + 10.seconds
      job.save!
    end

    it "should be called after commit, when a record is saved" do
      allow(new_job).to receive(:tomqueue_publish) { @called = true }
      Delayed::Job.transaction do
        new_job.save!

        expect(@called).to be_nil
      end
      expect(@called).to be_truthy
    end

    it "should be called after commit, when a record is updated" do
      allow(job).to receive(:tomqueue_publish) { @called = true }
      Delayed::Job.transaction do
        job.run_at = Time.now + 10.seconds
        job.save!
        expect(@called).to be_nil
      end

      expect(@called).to be_truthy
    end

    it "should not be called when a record is destroyed" do
      expect(job).to_not receive(:tomqueue_publish)
      job.destroy
    end

    it "should not be called by a destroy in a transaction" do
      expect(job).to_not receive(:tomqueue_publish)
      Delayed::Job.transaction { job.destroy }
    end

    it "should not be called if the update transaction is rolled back" do
      allow(job).to receive(:tomqueue_publish) { @called = true }

      Delayed::Job.transaction do
        job.run_at = Time.now + 10.seconds
        job.save!
        raise ActiveRecord::Rollback
      end
      expect(@called).to be_nil
    end

    it "should not be called if the create transaction is rolled back" do
      expect(job).to_not receive(:tomqueue_publish)

      Delayed::Job.transaction do
        new_job.save!
        raise ActiveRecord::Rollback
      end
      expect(@called).to be_nil
    end
  end

  describe "Delayed::Job.tomqueue_republish method" do
    before { Delayed::Job.delete_all }

    it "should exist" do
      expect(Delayed::Job.respond_to?(:tomqueue_republish)).to be_truthy
    end

    it "should return nil" do
      expect(Delayed::Job.tomqueue_republish).to be_nil
    end

    it "should call #tomqueue_publish on all DB records" do
      10.times { Delayed::Job.create! }

      Delayed::Job.tomqueue_manager.queues[TomQueue::NORMAL_PRIORITY].purge
      queue = Delayed::Job.tomqueue_manager.queues[TomQueue::NORMAL_PRIORITY]
      expect(queue.message_count).to eq(0)

      Delayed::Job.tomqueue_republish
      sleep 0.25
      expect(queue.message_count).to eq(10)
    end

    it "should work with ActiveRecord scopes" do
      first_ids = 10.times.collect { Delayed::Job.create!.id }
      second_ids = 7.times.collect { Delayed::Job.create!.id }

      Delayed::Job.tomqueue_manager.queues[TomQueue::NORMAL_PRIORITY].purge
      queue = Delayed::Job.tomqueue_manager.queues[TomQueue::NORMAL_PRIORITY]
      expect(queue.message_count).to eq(0)

      Delayed::Job.where('id IN (?)', second_ids).tomqueue_republish
      sleep 0.25
      expect(queue.message_count).to eq(7)
    end

  end

  describe "Delayed::Job.acquire_locked_job" do
    let(:time) { Delayed::Job.db_time_now }
    before { allow(Delayed::Job).to receive(:db_time_now).and_return(time) }

    let(:job) { Delayed::Job.create! }
    let(:worker) { Delayed::Worker.new }

    # make sure the job exists!
    before { job }

    subject { Delayed::Job.acquire_locked_job(job.id, worker, &@block) }

    describe "when the job doesn't exist" do
      before { job.destroy }

      it "should return nil" do
        expect(subject).to be_nil
      end

      it "should not yield if a block is provided" do
        @block = lambda { |value| @called = true}
        subject
        expect(@called).to be_nil
      end
    end

    describe "when the job exists" do

      it "should hold an explicit DB lock whilst performing the lock" do
        pending("Only possible when using mysql2 adapter (ADAPTER=mysql environment)") unless ActiveRecord::Base.connection.class.to_s == "ActiveRecord::ConnectionAdapters::Mysql2Adapter"

        # Ok, fudge a second parallel connection to MySQL
        second_connection = ActiveRecord::Base.connection.dup
        second_connection.reconnect!
        ActiveRecord::Base.connection.reset!

        # Assert we have separate connections
        expect(second_connection.execute("SELECT connection_id() as id;").first).to_not eq(
          ActiveRecord::Base.connection.execute("SELECT connection_id() as id;").first)

        # This is called in a thread when the transaction is open to query the job, store the response
        # and the time when the response comes back
        parallel_query = lambda do |job_id|
          begin
            # Simulate another worker performing a SELECT ... FOR UPDATE request
            @query_result = second_connection.execute("SELECT locked_at, locked_by FROM delayed_jobs WHERE id=#{job_id} LIMIT 1 FOR UPDATE").first
            @query_returned_at = Time.now.to_f
          rescue
            puts "Failed #{$!.inspect}"
          end
        end

        # When we have the transaction open, we emit a query on a parallel thread and check the timing
        @block = lambda do |job|
          @thread = Thread.new(job.id, &parallel_query)
          sleep 0.25
          @leaving_transaction_at = Time.now.to_f
          true
        end

        # Kick it all off !
        subject

        @thread.join

        # now make sure the parallel thread blocked until the transaction returned
        expect(@query_returned_at).to be > @leaving_transaction_at

        # make sure the returned record showed the lock
        expect(@query_result[0]).to_not be_nil
        expect(@query_result[1]).to_not be_nil
      end

      describe "when the job is marked as failed" do
        let(:failed_time) { Time.now - 10 }

        before do
          job.update_attribute(:failed_at, failed_time)
        end

        it "should return nil" do
          expect(subject).to be_nil
        end

        it "should not modify the failed_at value" do
          subject
          job.reload
          expect(job.failed_at.to_i).to eq(failed_time.to_i)
        end

        it "should not lock the job" do
          subject
          job.reload
          expect(job.locked_by).to be_nil
          expect(job.locked_at).to be_nil
        end
      end

      describe "when the notification is delivered too soon" do

        before do
          actual_time = Delayed::Job.db_time_now
          allow(Delayed::Job).to receive(:db_time_now).and_return(actual_time - 10)
        end

        it "should return nil" do
          expect(subject).to be_nil
        end

        it "should re-post a notification" do
          expect(Delayed::Job.tomqueue_manager).to receive(:publish) do |payload, args|
            expect(args[:run_at].to_i).to eq(job.run_at.to_i)
          end
          subject
        end

        it "should not lock the job" do
          subject
          job.reload
          expect(job.locked_by).to be_nil
          expect(job.locked_at).to be_nil
        end

      end

      describe "when the job is not locked" do

        it "should acquire the lock fields on the job" do
          subject
          job.reload
          expect(job.locked_at.to_i).to eq(time.to_i)
          expect(job.locked_by).to eq(worker.name)
        end

        it "should return the job object" do
          expect(subject).to be_a(Delayed::Job)
          expect(subject.id).to eq(job.id)
        end

        it "should yield the job to the block if present" do
          @block = lambda { |value| @called = value}
          subject
          expect(@called).to be_a(Delayed::Job)
          expect(@called.id).to eq(job.id)
        end

        it "should not have locked the job when the block is called" do
          @block = lambda { |job| @called = [job.id, job.locked_at, job.locked_by]; true }
          subject
          expect(@called).to eq([job.id, nil, nil])
        end

        describe "if the supplied block returns true" do
          before { @block = lambda { |_| true } }

          it "should lock the job" do
            subject
            job.reload
            expect(job.locked_at.to_i).to eq(time.to_i)
            expect(job.locked_by).to eq(worker.name)
          end

          it "should return the job" do
            expect(subject).to be_a(Delayed::Job)
            expect(subject.id).to eq(job.id)
          end
        end

        describe "if the supplied block returns false" do
          before { @block = lambda { |_| false } }

          it "should not lock the job" do
            subject
            job.reload
            expect(job.locked_at).to be_nil
            expect(job.locked_by).to be_nil
          end

          it "should return nil" do
            expect(subject).to be_nil
          end
        end
      end

      describe "when the job is locked with a valid lock" do

        before do
          @old_locked_by = job.locked_by = "some worker"
          @old_locked_at = job.locked_at = Time.now
          job.save!
        end

        it "should not yield to a block if provided" do
          @called = false
          @block = lambda { |_| @called = true}
          subject
          expect(@called).to be_falsy
        end

        it "should return false" do
          expect(subject).to be_falsy
        end

        it "should not change the lock" do
          subject
          job.reload
          expect(job.locked_by).to eq(@old_locked_by)
          expect(job.locked_at.to_i).to eq(@old_locked_at.to_i)
        end

      end

      describe "when the job is locked with a stale lock" do
        before do
          @old_locked_by = job.locked_by = "some worker"
          @old_locked_at = job.locked_at = (Time.now - Delayed::Worker.max_run_time - 1)
          job.save!
        end

        it "should return the job" do
          expect(subject).to be_a(Delayed::Job)
          expect(subject.id).to eq(job.id)
        end

        it "should update the lock" do
          subject
          job.reload
          expect(job.locked_at).to_not eq(@old_locked_at)
          expect(job.locked_by).to_not eq(@old_locked_by)
        end

        # This is tricky - if we have a stale lock, the job object
        # will have been updated by the first worker, so the digest will
        # now be invalid (since updated_at will have changed)
        #
        # So, we don't yield, we just presume we're carrying on from where
        # a previous worker left off and don't try and validate the job any
        # further.
        it "should not yield the block if supplied" do
          @called = false
          @block = lambda { |_| @called = true}
          subject
          expect(@called).to be_falsy
        end
      end

    end
  end

  describe "Delayed::Job.reserve - return the next job" do
    let(:job)     { Delayed::Job.create! }
    let(:worker)  { double("Worker", :name => "Worker-Name-#{Time.now.to_f}") }
    let(:payload) { job.tomqueue_payload }
    let(:work)    { double("Work", :payload => payload, :ack! => nil) }

    subject { Delayed::Job.reserve(worker) }

    before do
      allow(Delayed::Job.tomqueue_manager).to receive(:pop).and_return(work)
    end

    it "should call pop on the queue manager" do
      expect(Delayed::Job.tomqueue_manager).to receive(:pop)

      subject
    end

    describe "signal handling" do
      it "should allow signal handlers during the pop" do
        Delayed::Worker.raise_signal_exceptions = false
        expect(Delayed::Job.tomqueue_manager).to receive(:pop) do
          expect(Delayed::Worker.raise_signal_exceptions).to be_truthy
          work
        end
        Delayed::Job.reserve(worker)
      end

      it "should reset the signal handler var after the pop" do
        Delayed::Worker.raise_signal_exceptions = false
        subject
        expect(Delayed::Worker.raise_signal_exceptions).to eq(false)
      end

      it "should reset the signal handler var even if it's already true" do
        Delayed::Worker.raise_signal_exceptions = true
        subject
        expect(Delayed::Worker.raise_signal_exceptions).to eq(true)
      end

      it "should not allow signal exceptions to escape the function" do
        allow(Delayed::Job.tomqueue_manager).to receive(:pop) do
          raise SignalException, "INT"
        end

        expect { subject }.not_to raise_error
      end

      it "should allow exceptions to escape the function" do
        allow(Delayed::Job.tomqueue_manager).to receive(:pop) do
          raise Exception, "Something went wrong"
        end
        expect { subject }.to raise_error(Exception)
      end
    end

    describe "if a nil message is popped" do
      before { allow(Delayed::Job.tomqueue_manager).to receive(:pop).and_return(nil) }

      it "should return nil" do
        expect(subject).to be_nil
      end

      it "should sleep for a second to avoid potentially tight loops" do
        start_time = Time.now
        subject
        expect(Time.now - start_time).to be > 1.0
      end
    end

    describe "if the work payload doesn't cleanly JSON decode" do
      before { TomQueue.logger = Logger.new("/dev/null") }

      let(:payload) { "NOT JSON!!1" }

      it "should report an exception" do
        TomQueue.exception_reporter = double("Reporter", :notify => nil)
        expect(TomQueue.exception_reporter).to receive(:notify).with(instance_of(JSON::ParserError))
        subject
      end

      it "should be happy if no exception reporter is set" do
        TomQueue.exception_reporter = nil
        subject
      end

      it "should ack the message" do
        expect(work).to receive(:ack!)
        subject
      end

      it "should log an error" do
        expect(TomQueue.logger).to receive(:error)
        subject
      end

      it "should return nil" do
        expect(subject).to be_nil
      end
    end

    it "should call acquire_locked_job with the job_id and the worker" do
      expect(Delayed::Job).to receive(:acquire_locked_job).with(job.id, worker)
      subject
    end

    it "should attach a block to the call to acquire_locked_job" do
      def stub_implementation(job_id, worker, &block)
        expect(block).to_not be_nil
      end
      allow(Delayed::Job).to receive(:acquire_locked_job, &method(:stub_implementation)).and_return(job)
      subject
    end

    describe "the block provided to acquire_locked_job" do
      before do |test|
        def stub_implementation(job_id, worker, &block)
          @block = block
        end
        allow(Delayed::Job).to receive(:acquire_locked_job, &method(:stub_implementation)).and_return(job)
      end

      it "should return true if the digest in the message payload matches the job" do
        subject
        expect(@block.call(job)).to be_truthy
      end

      it "should return false if the digest in the message payload doesn't match the job" do
        subject
        job.touch(:updated_at)
        expect(@block.call(job)).to be_truthy
      end

      it "should return true if there is no digest in the payload object" do
        allow(work).to receive(:payload).and_return(JSON.dump(JSON.load(payload).merge("delayed_job_digest" => nil)))
        subject
        expect(@block.call(job)).to be_truthy
      end

    end

    describe "when acquire_locked_job returns the job object" do
      # A.K.A We have a locked job!

      let(:returned_job) { Delayed::Job.find(job.id) }
      before { allow(Delayed::Job).to receive(:acquire_locked_job).and_return(returned_job) }

      it "should not ack the message" do
        expect(work).to_not receive(:ack!)
        subject
      end

      it "should return the Job object" do
        expect(subject).to eq(returned_job)
      end

      it "should associate the message object with the job" do
        expect(subject.tomqueue_work).to eq(work)
      end

    end

    describe "when acquire_locked_job returns false" do
      # A.K.A The lock is held by another worker.
      #  - we post a notification to re-try after the max_run_time

      before do
        job.locked_at = Delayed::Job.db_time_now - 10
        job.locked_by = "foobar"
        job.save!
        allow(Delayed::Job).to receive(:acquire_locked_job).and_return(false)
      end

      it "should ack the message" do
        expect(work).to receive(:ack!)
        subject
      end

      it "should publish a notification for after the max-run-time of the job" do
        expect(Delayed::Job.tomqueue_manager).to receive(:publish) do |payload, opts|
          expect(opts[:run_at].to_i).to eq(job.locked_at.to_i + Delayed::Worker.max_run_time + 1)
        end
        subject
      end

      it "should return nil" do
        expect(subject).to be_nil
      end

    end

    describe "when acquire_locked_job returns nil" do
      # A.K.A The job doesn't exist anymore!
      #  - we're done!

      before { allow(Delayed::Job).to receive(:acquire_locked_job).and_return(nil) }

      it "should ack the message" do
        expect(work).to receive(:ack!)
        subject
      end

      it "should return nil" do
        expect(subject).to be_nil
      end

    end

    describe "when SignalException raised before work found" do
      let(:work) { double("Work", :payload => payload, :nack! => nil) }

      before do
        allow(Delayed::Job.tomqueue_manager).to receive(:pop).and_raise(SignalException.new("QUIT"))
      end

      it "should return nil" do
        expect(subject).to be_nil
      end
    end

    describe "when Exception raised before work found" do
      let(:work) { double("Work", :payload => payload, :nack! => nil) }

      before do
        allow(Delayed::Job.tomqueue_manager).to receive(:pop).and_raise(Exception)
      end

      it "should raise exception" do
        expect { subject }.to raise_error(Exception)
      end
    end

    describe "when SignalException after work found" do
      let(:work) { double("Work", :payload => payload, :nack! => nil) }

      before do
        allow(Delayed::Job).to receive(:acquire_locked_job).and_raise(SignalException.new("QUIT"))
      end

      it "should nack the work" do
        expect(work).to receive(:nack!)
        subject
      end

      it "should return nil" do
        expect(subject).to be_nil
      end
    end

    describe "when Exception after work found" do
      let(:work) { double("Work", :payload => payload, :nack! => nil) }

      before do
        expect(Delayed::Job).to receive(:acquire_locked_job).and_raise(Exception)
      end

      it "should nack the work" do
        expect(work).to receive(:nack!)
        begin
          subject
        rescue Exception
        end
      end

      it "should raise exception" do
        expect { subject }.to raise_error(Exception)
      end
    end

  end

  describe "Job#invoke_job" do
    let(:payload) { double("DelayedJobPayload", :perform => nil)}
    let(:job) { Delayed::Job.create!(:payload_object=>payload) }

    it "should perform the job" do
      expect(payload).to receive(:perform)
      job.invoke_job
    end

    it "should not have a problem if tomqueue_work is nil" do
      job.tomqueue_work = nil
      job.invoke_job
    end
  end


end
