require "spec_helper"

describe "Job Failure", worker: true do
  class FailingJob < TestJob
    def perform
      raise "Epic Fail!"
    end

    def reschedule_at(current_time, _)
      current_time + (0.1).seconds
    end
  end

  let(:payload) { FailingJob.new("Foo") }

  it "should increment attempts" do
    job = Delayed::Job.enqueue(payload)
    expect(job.attempts).to eq(0)
    expect(payload).to error
    sleep(0.1)
    expect(job.reload.attempts).to eq(1)
    expect(job.last_error).to match(/Epic Fail!/)
  end

  it "should set failed_at on permanent failure" do
    job = Delayed::Job.enqueue(payload)
    expect(payload).to error
    sleep(0.1)
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
