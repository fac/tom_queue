require "spec_helper"
require "progress_bar"

JOB_COUNT = (ENV["JOB_COUNT"] || 100_000).to_i
WORKER_COUNT = (ENV["WORKER_COUNT"] || 10).to_i

if ENV["STRESS_TESTS"]
  SanityTestJob = Struct.new(:id) do
    def perform
      TomQueue.test_logger.debug("RUNNING(#{id})")
    end
  end

  describe "Stress tests" do
    it "should run #{JOB_COUNT} jobs once each, spread over #{WORKER_COUNT} worker processes" do

      puts "Enqueuing #{JOB_COUNT} jobs"
      progress = ProgressBar.new(JOB_COUNT)

      JOB_COUNT.times do |i|
        Delayed::Job.enqueue(SanityTestJob.new(i))
        progress.increment!
      end

      with_workers(WORKER_COUNT) do
        # Check all the jobs have run
        messages = worker_messages(JOB_COUNT, (JOB_COUNT * 0.1).seconds)
        expect(messages.length).to eq(JOB_COUNT) # one message per job
        expect(worker_messages(1, 5.seconds)).to be_empty # no more messages == no more jobs to run

        # Check the jobs have run once each
        jobs_run = messages.map { |message| message.match(/RUNNING\((\d+)\)/)[1] }.uniq
        expect(jobs_run.length).to eq(JOB_COUNT)

        # Check the jobs are spread over all workers
        worker_pids = messages.map { |message| message.match(/#(\d+)/)[1] }.uniq
        expect(worker_pids.length).to eq(WORKER_COUNT)
      end
    end
  end
end
