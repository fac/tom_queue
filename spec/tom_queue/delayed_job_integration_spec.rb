require 'tom_queue/helper'

describe Delayed::Job, "integration spec" do
    
  class TestJobClass
    cattr_accessor :perform_hook
    
    @@flunk_count = 0
    cattr_accessor :flunk_count 
    
    def initialize(name)
      @name = name
    end

    def perform
      @@perform_hook && @@perform_hook.call(@name)

      if @@flunk_count > 0
        @@flunk_count -= 1
        raise RuntimeError, "Failed to run job"
      end
    end

    def reschedule_at(time, attempts)
      time + 0.5
    end

  end

  let(:job_name) { "Job-#{Time.now.to_f}"}

  before do
    # Clean-slate ...
    TomQueue.default_prefix = "tomqueue.test"
    TomQueue.hook_delayed_job!
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
    Delayed::Job.tomqueue_manager.purge!
    Delayed::Job.delete_all
    
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
      Delayed::Job.enqueue(TestJobClass.new("job1"), :run_at => Time.now + 0.1)
      Delayed::Job.enqueue(TestJobClass.new("job2"), :run_at => Time.now + 0.05)
      Delayed::Worker.new.work_off(2).should == [2, 0]
    }.should > 0.1
    @called.should == ["job2", "job1"]
  end

  it "should support job priorities" do
    TomQueue::DelayedJobHook::Job.tomqueue_priority_map[0] = TomQueue::NORMAL_PRIORITY
    TomQueue::DelayedJobHook::Job.tomqueue_priority_map[1] = TomQueue::HIGH_PRIORITY
    Delayed::Job.enqueue(TestJobClass.new("low1"), :priority => 0)
    Delayed::Job.enqueue(TestJobClass.new("low2"), :priority => 0)
    Delayed::Job.enqueue(TestJobClass.new("high"), :priority => 1)
    Delayed::Job.enqueue(TestJobClass.new("low3"), :priority => 0)
    Delayed::Job.enqueue(TestJobClass.new("low4"), :priority => 0)
    Delayed::Worker.new.work_off(5)
    @called.should == ["high", "low1", "low2", "low3", "low4"]
  end

end