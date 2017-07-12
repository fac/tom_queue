require "tom_queue/helper"
require "tom_queue/plugin"

describe TomQueue::Worker do

  describe ".lifecycle" do
    class WorkerTestPlugin < TomQueue::Plugin
      cattr_accessor :traces
      self.traces = []

      def self.trace(*args)
        traces << args
      end

      callbacks do |lifecycle|
        trace(lifecycle)
        lifecycle.before(:enqueue) do |job|
          WorkerTestPlugin.trace(:enqueue, job)
        end
      end
    end

    before do
      WorkerTestPlugin.traces = []
    end

    it "should instantiate a @lifecycle instance with specified plugins" do
      TomQueue::Worker.plugins = [WorkerTestPlugin]
      mock_lifecycle = TomQueue::Lifecycle.new
      allow(TomQueue::Lifecycle).to receive(:new).and_return(mock_lifecycle)

      expect(TomQueue::Worker.lifecycle).to eq(mock_lifecycle)
      expect(WorkerTestPlugin.traces.length).to eq(1)
      expect(WorkerTestPlugin.traces[0]).to eq([mock_lifecycle])
    end
  end

  describe ".delay_job?" do
    let(:job) { instance_double("TomQueue::Persistence::Model") }

    it "should default to true" do
      expect(TomQueue::Worker.delay_job?(job)).to be_truthy
    end

    it "should be configurable" do
      begin
        TomQueue::Worker.delay_jobs = false
        expect(TomQueue::Worker.delay_job?(job)).to be_falsy
      ensure
        TomQueue::Worker.delay_jobs = TomQueue::Worker::DEFAULT_DELAY_JOBS
      end
    end

    it "should allow a proc to determine the result" do
      begin
        TomQueue::Worker.delay_jobs = lambda { |job| job.present? }
        expect(TomQueue::Worker.delay_job?(job)).to be_truthy
        expect(TomQueue::Worker.delay_job?(nil)).to be_falsy
      ensure
        TomQueue::Worker.delay_jobs = TomQueue::Worker::DEFAULT_DELAY_JOBS
      end
    end
  end

  describe "#max_run_time" do
    let(:worker) { TomQueue::Worker.new }

    it "should respect the job's max_run_time" do
      job = instance_double("TomQueue::Persistence::Model", max_run_time: 5.minutes)
      expect(worker.max_run_time(job)).to eq(5.minutes)
    end

    it "should use the default if not configured" do
      job = instance_double("TomQueue::Persistence::Model", max_run_time: nil)
      expect(worker.max_run_time(job)).to eq(worker.class::DEFAULT_MAX_RUN_TIME)
    end

    it "should use the configured value" do
      begin
        worker.class.max_run_time = 1.hour
        job = instance_double("TomQueue::Persistence::Model", max_run_time: nil)
        expect(worker.max_run_time(job)).to eq(1.hour)
      ensure
        worker.class.max_run_time = worker.class::DEFAULT_MAX_RUN_TIME
      end
    end
  end

  describe "#max_attempts" do
    let(:worker) { TomQueue::Worker.new }

    it "should respect the job's max_attempts" do
      job = instance_double("TomQueue::Persistence::Model", max_attempts: 2)
      expect(worker.max_attempts(job)).to eq(2)
    end

    it "should use the default if not configured" do
      job = instance_double("TomQueue::Persistence::Model", max_attempts: nil)
      expect(worker.max_attempts(job)).to eq(worker.class::DEFAULT_MAX_ATTEMPTS)
    end

    it "should use the configured value" do
      begin
        worker.class.max_attempts = 10
        job = instance_double("TomQueue::Persistence::Model", max_attempts: nil)
        expect(worker.max_attempts(job)).to eq(10)
      ensure
        worker.class.max_attempts = worker.class::DEFAULT_MAX_ATTEMPTS
      end
    end
  end

  describe "#work_off" do
    let(:worker) { TomQueue::Worker.new }

    it "should work off the given number of jobs" do
      expect(TomQueue::Worker::Stack).to \
        receive(:call).with(worker: worker).
        exactly(10).times { true }

      worker.work_off(10)
    end

    it "should return successes and failures" do
      calls = 0
      expect(TomQueue::Worker::Stack).to receive(:call).with(worker: worker).exactly(5).times do
        calls += 1
        (calls % 2) == 1
      end

      expect(worker.work_off(5)).to eq([3, 2])
    end

    it "should stop when the stack returns a non-boolean result" do
      calls = 0
      expect(TomQueue::Worker::Stack).to receive(:call).with(worker: worker).exactly(4).times do |options|
        calls += 1
        calls == 4 ? nil : (calls % 2) == 1
      end

      expect(worker.work_off(5)).to eq([2, 1])
    end

    it "should stop when the worker is stopped" do
      calls = 0
      expect(TomQueue::Worker::Stack).to receive(:call).with(worker: worker).exactly(3).times do |options|
        calls += 1
        options[:worker].stop if calls == 3
        (calls % 2) == 1
      end

      expect(worker.work_off(5)).to eq([2, 1])
    end
  end

  describe "#start" do
    let(:worker) { TomQueue::Worker.new }

    it "should run until the worker is stopped" do
      calls = 0
      expect(TomQueue::Worker::Stack).to receive(:call).with(worker: worker).exactly(3).times do |options|
        calls += 1
        options[:worker].stop if calls == 3
        (calls % 2) == 1
      end

      worker.start
    end
  end

  describe "signals" do
    let(:worker) { TomQueue::Worker.new }

    before do
      allow(TomQueue::Worker::Stack).to receive(:call).and_return(true)
    end

    ["TERM", "INT"].each do |signal|
      it "should shut down cleanly when receiving a #{signal} signal" do
        pid = fork do
          worker.start
        end

        if pid
          sleep(1)
          Process.kill(signal, pid)
          Process.wait(pid)
          status = $?
          expect(status).to be_a(Process::Status)
          expect(status).to be_exited
          expect(status.exitstatus).to eq(0)
        end
      end
    end
  end
end
