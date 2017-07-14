require "spec_helper"

describe "Failing job", worker: true do
  class FailingJob < TestJob
    def perform
      super
      raise "Epic Fail!"
    end

    def reschedule_at(current_time, _)
      current_time + 0.2
    end

    def max_attempts
      2
    end
  end

  class FailOnceJob < FailingJob
    def before(job)
      super
      @should_pass = job.attempts > 0
    end

    def perform
      log("RUNNING: #{id}")
      raise "Epic Fail!" unless @should_pass
    end
  end

  it "should increment attempts and set failed_at on permanent failure" do
    payload = FailingJob.new("FailMe")
    job = Delayed::Job.enqueue(payload)
    expect(job.attempts).to eq(0)

    # First Attempt
    messages = worker_messages(4)
    expect(messages[0]).to match(/BEFORE_HOOK: FailMe/)
    expect(messages[1]).to match(/RUNNING: FailMe/)
    expect(messages[2]).to match(/ERROR_HOOK: FailMe/)
    expect(messages[3]).to match(/AFTER_HOOK: FailMe/)
    wait(1.second).for { job.reload.attempts }.to eq(1)
    expect(job.failed_at).to be_nil

    # Second Attempt
    messages = worker_messages(5)
    expect(messages[0]).to match(/BEFORE_HOOK: FailMe/)
    expect(messages[1]).to match(/RUNNING: FailMe/)
    expect(messages[2]).to match(/ERROR_HOOK: FailMe/)
    expect(messages[3]).to match(/AFTER_HOOK: FailMe/)
    expect(messages[4]).to match(/FAILURE_HOOK: FailMe/)
    wait(1.second).for { job.reload.attempts }.to eq(2)
    expect(job.failed_at).not_to be_nil
  end

  it "should retry until successful then clean up the database" do
    payload = FailOnceJob.new("FailThenPass")
    job = Delayed::Job.enqueue(payload)
    messages = worker_messages(8)
    expect(messages[0]).to match(/BEFORE_HOOK: FailThenPass/)
    expect(messages[1]).to match(/RUNNING: FailThenPass/)
    expect(messages[2]).to match(/ERROR_HOOK: FailThenPass/)
    expect(messages[3]).to match(/AFTER_HOOK: FailThenPass/)
    expect(messages[4]).to match(/BEFORE_HOOK: FailThenPass/)
    expect(messages[5]).to match(/RUNNING: FailThenPass/)
    expect(messages[6]).to match(/SUCCESS_HOOK: FailThenPass/)
    expect(messages[7]).to match(/AFTER_HOOK: FailThenPass/)
    wait(1.second).for { Delayed::Job.where(id: job.id).first }.to be_nil
  end
end
