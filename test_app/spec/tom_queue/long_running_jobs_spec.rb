require "spec_helper"

describe "Long running jobs", worker: true do
  class LongRunningJob < TestJob
    def perform
      super
      sleep(2)
    end

    def max_run_time
      1
    end

    def reschedule_at(current_time, _)
      current_time + 1.minute
    end
  end

  specify "should fail" do
    payload = LongRunningJob.new("TooSlow")
    job = Delayed::Job.enqueue(payload)
    messages = worker_messages(4)
    expect(messages[0]).to match(/BEFORE_HOOK: TooSlow/)
    expect(messages[1]).to match(/RUNNING: TooSlow/)
    expect(messages[2]).to match(/ERROR_HOOK: TooSlow/)
    expect(messages[2]).to match(/execution expired/)
    expect(messages[3]).to match(/AFTER_HOOK: TooSlow/)
    wait(1.second).for { job.reload.attempts }.to eq(1)
    expect(job.locked_at).to be_nil
    expect(job.run_at).to be_within(1.second).of(1.minute.from_now)
  end
end
