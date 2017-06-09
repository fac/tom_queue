require "spec_helper"

describe "Job prioritisation", worker: true do
  let(:lowest_priority) { TestJob.new("LowestPriority") }
  let(:low_priority) { TestJob.new("LowPriority") }
  let(:normal_priority) { TestJob.new("NormalPriority") }
  let(:high_priority) { TestJob.new("HighPriority") }
  let(:payloads) {
    {
      LOWEST_PRIORITY => lowest_priority,
      LOW_PRIORITY => low_priority,
      NORMAL_PRIORITY => normal_priority,
      HIGH_PRIORITY => high_priority
    }
  }

  xspecify "should run scheduled jobs in order" do
    start_time = 2.seconds.from_now
    # Randomise the order in which jobs are enqueued, but schedule them all for the same time
    jobs = JOB_PRIORITIES.shuffle.map do |priority|
      Delayed::Job.enqueue(payloads[priority], priority: priority, run_at: start_time)
    end
    wait.for { Time.now }.to be <= start_time

    messages = worker_messages(12).select { |message| message =~ /RUNNING/ } # 4 per job, extract the run notification
    expect(messages[0]).to match(/HighPriority/)
    expect(messages[1]).to match(/NormalPriority/)
    expect(messages[2]).to match(/LowPriority/)
    expect(messages[3]).to match(/LowestPriority/)
  end
end
