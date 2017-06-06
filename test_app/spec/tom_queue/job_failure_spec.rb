require "spec_helper"

describe "Job Failure" do
  FailingJob = Struct.new(:options) do
    def perform
      raise "Epic Fail!"
    end

    def max_attempts
      options[:max_attempts] || 5
    end
  end

  it "should increment attempts" do
    with_worker do |worker|
      job = Delayed::Job.enqueue(FailingJob.new({}))
      expect(job.attempts).to eq(0)
      worker.step
      expect(job.reload.attempts).to eq(1)
    end
  end

  it "should set last_error" do
    with_worker do |worker|
      job = Delayed::Job.enqueue(FailingJob.new({}))
      worker.step
      expect(job.reload.last_error).to match(/Epic Fail!/)
    end
  end

  it "should set failed_at on permanent failure" do
    with_worker do |worker|
      job = Delayed::Job.enqueue(FailingJob.new({max_attempts: 2}))
      worker.step
      expect(job.reload.attempts).to eq(1)
      expect(job.failed_at).to be_nil
      worker.step
      expect(job.reload.attempts).to eq(2)
      expect(job.failed_at).to be_a(DateTime)
    end
  end

  describe "backoff" do

  end

  describe "permanent failure" do

  end
end
