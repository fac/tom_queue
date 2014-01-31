require 'spec_helper'

describe Delayed::Job, "integration spec", :timeout => 10 do

  class TestJobClass
    cattr_accessor :perform_hook

    @@flunk_count = 0
    cattr_accessor :flunk_count

    @@asplode_count = 0
    cattr_accessor :asplode_count

    def initialize(name)
      @name = name
    end

    def perform
      @@perform_hook && @@perform_hook.call(@name)

      if @@asplode_count > 0
        @@asplode_count -= 1
        Thread.exit
      end

      if @@flunk_count > 0
        @@flunk_count -= 1
        raise RuntimeError, "Failed to run job"
      end
    end

    def reschedule_at(time, attempts)
      time + 0.5
    end

  end

  let(:job_name) { "Job-#{Time.now.to_f}" }

  before do
    # Clean-slate ...
    TomQueue.default_prefix = "test-#{Time.now.to_f}"
    TomQueue::DelayedJob.apply_hook!
    Delayed::Job.delete_all
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)

    # Keep track of how many times the job is run
    @called = []
    TestJobClass.perform_hook = lambda { |name| @called << name }

    # Reset the flunk count
    TestJobClass.flunk_count = 0
  end

  it "should actually be using the queue" do
    Delayed::Job.enqueue(TestJobClass.new(job_name))

    Delayed::Job.tomqueue_manager.queues[TomQueue::NORMAL_PRIORITY].status[:message_count].should == 1
  end

  it "should integrate with Delayed::Worker" do
    Delayed::Job.enqueue(TestJobClass.new(job_name))

    Delayed::Worker.new.work_off(1).should == [1, 0] # 1 success, 0 failed
    @called.first.should == job_name
  end

  it "should still back-off jobs" do
    Delayed::Job.enqueue(TestJobClass.new(job_name))
    TestJobClass.flunk_count = 1

    Benchmark.realtime {
      Delayed::Worker.new.work_off(1).should == [0, 1]
      Delayed::Worker.new.work_off(1).should == [1, 0]
    }.should > 0.5
  end

  it "should support run_at" do
    Benchmark.realtime {
      Delayed::Job.enqueue(TestJobClass.new("job1"), :run_at => Time.now + 0.5)
      Delayed::Job.enqueue(TestJobClass.new("job2"), :run_at => Time.now + 0.1)
      Delayed::Worker.new.work_off(2).should == [2, 0]
    }.should > 0.1
    @called.should == ["job2", "job1"]
  end

  it "should support job priorities" do
    TomQueue::DelayedJob.priority_map[0] = TomQueue::NORMAL_PRIORITY
    TomQueue::DelayedJob.priority_map[1] = TomQueue::HIGH_PRIORITY
    Delayed::Job.enqueue(TestJobClass.new("low1"), :priority => 0)
    Delayed::Job.enqueue(TestJobClass.new("low2"), :priority => 0)
    Delayed::Job.enqueue(TestJobClass.new("high"), :priority => 1)
    Delayed::Job.enqueue(TestJobClass.new("low3"), :priority => 0)
    Delayed::Job.enqueue(TestJobClass.new("low4"), :priority => 0)
    Delayed::Worker.new.work_off(5)
    @called.should == ["high", "low1", "low2", "low3", "low4"]
  end

  it "should not run a failed job" do
    logfile = Tempfile.new('logfile')
    TomQueue.logger = Logger.new(logfile.path)
    Delayed::Job.delete_all
    # this will send the notification
    job = "Hello".delay.to_s

    # now make the job look like it has failed
    job.attempts = 0
    job.failed_at = Time.now
    job.last_error = "Some error"
    job.save

    job.should be_failed

    Delayed::Job.tomqueue_republish

    # The job should get ignored for both runs
    Delayed::Worker.new.work_off(1)
    Delayed::Worker.new.work_off(1)

    # And, since it never got run, it should still exist!
    Delayed::Job.find_by_id(job.id).should_not be_nil
    # And it should have been noisy, too.
    File.read(logfile.path).should =~ /Received notification for failed job #{job.id}/
  end

  # it "should re-run the job once max_run_time is reached if, say, a worker crashes" do
  #   Delayed::Worker.max_run_time = 2

  #   job = Delayed::Job.enqueue(TestJobClass.new("work"))

  #   # This thread will be abruptly terminated mid-job
  #   TestJobClass.asplode_count = 1
  #   lock_stale_time = Time.now.to_f + Delayed::Worker.max_run_time
  #   Thread.new { Delayed::Worker.new.work_off(1) }.join

  #   # This will shutdown the various channels, which should result in the message being
  #   # returned to the broker.
  #   Delayed::Job.tomqueue_manager.setup_amqp!

  #   # Make sure the job is still locked
  #   job.reload
  #   job.locked_at.should_not be_nil
  #   job.locked_by.should_not be_nil

  #   # Now wait for the max_run_time, which is artificially low
  #   while Delayed::Job.find_by_id(job.id)
  #     Delayed::Worker.new.work_off(1)
  #   end

  #   # Ensure the worker blocked until the job's original lock was actually stale.
  #   Time.now.to_f.should > lock_stale_time.to_f
  # end

end
