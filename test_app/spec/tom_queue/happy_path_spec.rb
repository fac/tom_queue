require "spec_helper"

klass = job_class

describe "Job Queueing", worker: true do
  class JobClass < DummyJob; end

  before do
    JobClass.reset!
    expect(JobClass).not_to be_completed
  end

  it "should run the job immediately" do
    Delayed::Job.enqueue(JobClass.new("Foo"))
    expect(JobClass).to complete_within(1)
  end

  it "should not run a job scheduled for the future immediately" do
    Delayed::Job.enqueue(JobClass.new("Foo"), run_at: 1.minute.from_now)
    expect(JobClass).not_to complete_within(1)
  end
end
