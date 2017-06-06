require "spec_helper"

describe "Job Failure", worker: true do
  class FailingJob < DummyJob
    def perform
      raise "Epic Fail!"
    end

    def max_attempts
      2
    end
  end

  before do
    FailingJob.reset!
    expect(FailingJob).not_to be_completed
  end

  it "should increment attempts" do
    job = Delayed::Job.enqueue(FailingJob.new)
    expect(job.attempts).to eq(0)
    sleep(1)
    expect(job.reload.attempts).to eq(1)
    expect(job.last_error).to match(/Epic Fail!/)
  end

  it "should set failed_at on permanent failure" do
    job = Delayed::Job.enqueue(FailingJob.new)
    sleep(1)
    expect(job.reload.attempts).to eq(1)
    expect(job.failed_at).to be_nil
    sleep(1)
    expect(job.reload.attempts).to eq(2)
    expect(job.failed_at).to be_a(DateTime)
  end

  describe "backoff" do

  end

  describe "permanent failure" do

  end
end
