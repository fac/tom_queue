require "spec_helper"

describe "Job prioritisation" do
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

  specify "should run scheduled jobs in order" do
    # Randomise the order in which jobs are enqueued, but schedule them all for the same time
    jobs = JOB_PRIORITIES.shuffle.map do |priority|
      Delayed::Job.enqueue(payloads[priority], priority: priority)
    end

    with_worker do
      messages = worker_messages(16).select { |message| message =~ /RUNNING/ } # 4 per job, extract the run notification
      expect(messages[0]).to match(/HighPriority/)
      expect(messages[1]).to match(/NormalPriority/)
      expect(messages[2]).to match(/LowPriority/)
      expect(messages[3]).to match(/LowestPriority/)
    end
  end
end
