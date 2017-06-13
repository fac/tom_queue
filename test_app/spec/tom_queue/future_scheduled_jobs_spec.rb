require "spec_helper"

describe "Future scheduled jobs", worker: true do
  specify "should not run until the scheduled time" do
    payload = TestJob.new("WaitAMoment")
    enqueue_time = DateTime.now
    job = Delayed::Job.enqueue(payload, run_at: 2.seconds.from_now)

    expected_runtime = job.run_at.to_datetime
    expect(expected_runtime).to be_within(A_MOMENT).of(enqueue_time + 2.seconds)

    messages = worker_messages(4)
    expect(messages[0]).to match(/BEFORE_HOOK: WaitAMoment/)
    expect(messages[1]).to match(/RUNNING: WaitAMoment/)
    expect(messages[2]).to match(/SUCCESS_HOOK: WaitAMoment/)
    expect(messages[3]).to match(/AFTER_HOOK: WaitAMoment/)

    timestamps = message_timestamps(messages)
    expect(timestamps[0]).to be_within(A_MOMENT).of(expected_runtime)
  end
end
