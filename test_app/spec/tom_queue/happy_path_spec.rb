require "spec_helper"

describe "Job Queueing", worker: true do
  let(:payload) { TestJob.new("Foo") }

  it "should run the job immediately" do
    Delayed::Job.enqueue(payload)
    expect(payload).to complete.within(1)
  end

  it "should clean up the database once run" do
    job = Delayed::Job.enqueue(payload)
    expect(Delayed::Job.where(id: job.id).first).to be_present
    expect(payload).to complete.within(1)
    sleep(0.1) # Slight race condition here...
    expect(Delayed::Job.where(id: job.id).first).to be_nil
  end

  it "should not run a job scheduled for the future immediately" do
    Delayed::Job.enqueue(payload, run_at: 1.minute.from_now)
    expect(payload).not_to complete.within(1)
  end
end
