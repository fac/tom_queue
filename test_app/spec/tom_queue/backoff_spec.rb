require "spec_helper"

describe "Failed Job Backoff", worker: true do
  class BackoffJob < TestJob
    def perform
      super
      raise "Epic Fail!"
    end

    def max_attempts
      3
    end

    def reschedule_at(current_time, attempts)
      current_time + attempts.seconds
    end
  end

  it "should back off the job using reschedule_at" do
    payload = BackoffJob.new("Backoff")
    job = Delayed::Job.enqueue(payload)
    messages = worker_messages(13) # 3 x 4 messages per run + failure
    timestamps = message_timestamps(messages.select { |message| message =~ /RUNNING: Backoff/ })
    expect(timestamps[1]).to be_within(0.1).of(timestamps[0] + 1.second) # Second attempt = 1s delay
    expect(timestamps[2]).to be_within(0.1).of(timestamps[1] + 2.seconds) # Third attempt = 2s delay
  end
end
