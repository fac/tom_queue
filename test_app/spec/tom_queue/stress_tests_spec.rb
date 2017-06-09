require "spec_helper"
require "progress_bar"

if ENV["STRESS_TESTS"]
  JOB_COUNT = (ENV["JOB_COUNT"] || 100_000).to_i
  WORKER_COUNT = (ENV["WORKER_COUNT"] || 10).to_i

  FAILED_JOB_COUNT = JOB_COUNT / 2
  SUCCESSFUL_JOB_COUNT = JOB_COUNT - FAILED_JOB_COUNT

  SanityTestJob = Struct.new(:id) do
    def perform
      TomQueue.test_logger.debug("RUNNING(#{id})")
    end
  end

  SanityTestFailingJob = Struct.new(:id) do
    def perform
      TomQueue.test_logger.debug("FAILING(#{id})")
      raise "Nah"
    end

    def max_attempts
      1
    end
  end

  describe "Stress tests" do
    it "should run #{JOB_COUNT} successful jobs once each, spread over #{WORKER_COUNT} worker processes" do

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

    it "should run #{SUCCESSFUL_JOB_COUNT} successful jobs and #{FAILED_JOB_COUNT} failing jobs once each, spread over #{WORKER_COUNT} worker processes" do
      payloads = SUCCESSFUL_JOB_COUNT.times.map { |i| SanityTestJob.new(i) }
      payloads += FAILED_JOB_COUNT.times.map { |i| SanityTestFailingJob.new(i) }

      puts "Enqueuing #{JOB_COUNT} jobs"
      progress = ProgressBar.new(JOB_COUNT)
      payloads.shuffle.each do |payload|
        Delayed::Job.enqueue(payload)
        progress.increment!
      end

      with_workers(WORKER_COUNT) do
        # Check all the jobs have run
        messages = worker_messages(JOB_COUNT, (JOB_COUNT * 0.1).seconds)

        # Check total messages
        expect(messages.length).to eq(JOB_COUNT) # one message per job
        expect(worker_messages(1, 5.seconds)).to be_empty # no more messages == no more jobs to run

        # Check the jobs have run once each
        success_messages = messages.select { |message| message =~ /RUNNING/ }
        successful_ids = success_messages.map { |message| message.match(/RUNNING\((\d+)\)/)[1] }.uniq
        expect(successful_ids.length).to eq(SUCCESSFUL_JOB_COUNT)

        failure_messages = messages.select { |message| message =~ /FAILING/ }
        failed_ids = failure_messages.map { |message| message.match(/FAILING\((\d+)\)/)[1] }.uniq
        expect(failed_ids.length).to eq(FAILED_JOB_COUNT)

        # Check the jobs are spread over all workers
        worker_pids = messages.map { |message| message.match(/#(\d+)/)[1] }.uniq
        expect(worker_pids.length).to eq(WORKER_COUNT)

        # Check that the failed jobs remain in the database
        wait(1.second).for { Delayed::Job.count }.to eq(FAILED_JOB_COUNT)
      end
    end
  end
end
