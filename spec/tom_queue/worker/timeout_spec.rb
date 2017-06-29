require "tom_queue/helper"

describe TomQueue::Worker::Timeout do
  let(:klass) { TomQueue::Worker::Timeout }

  describe "#call" do
    let(:chain) { Proc.new { |*a| sleep 2 } }
    let(:instance) { klass.new(chain) }

    it "should call the chain" do
      expect(chain).to receive(:call).with({}).once
      expect { instance.call({}) }.not_to raise_error
    end

    it "should raise a TomQueue::WorkerTimeout if it exceeds the job's runtime" do
      allow(klass).to receive(:max_run_time).with(any_args).and_return(1)
      expect { instance.call({}) }.to raise_error(TomQueue::WorkerTimeout)
    end
  end

  describe ".max_run_time(job)" do
    it "should use max_run_time from the job if available" do
      job = instance_double(TomQueue::Persistence::Model, max_run_time: 123)
      expect(klass.max_run_time(job: job)).to eq(123)
    end

    it "should default to TomQueue::Worker.max_run_time" do
      job = instance_double(TomQueue::Persistence::Model, max_run_time: nil)
      expect(klass.max_run_time(job: job)).to eq(TomQueue::Worker.max_run_time)
    end
  end

  describe ".max_run_time(work)" do
    it "should default to TomQueue::Worker.max_run_time" do
      expect(klass.max_run_time(work: "foo")).to eq(TomQueue::Worker.max_run_time)
    end
  end
end
