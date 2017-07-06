require "tom_queue/helper"

describe TomQueue::Enqueue::Publish do
  class TestJob
    def perform
      # noop
    end
  end

  let(:instance) { TomQueue::Enqueue::Publish.new }

  describe "for a TomQueue::Persistence::Model" do
    let(:job) { TomQueue::Persistence::Model.create!(payload_object: TestJob.new) }
    let(:payload) { job.payload }

    it "should publish the job to the queue" do
      expect(TomQueue::Enqueue::Publish.queue_manager).to receive(:publish).with(payload, run_at: job.run_at, priority: TomQueue::NORMAL_PRIORITY).once
      instance.call(job, {})
    end

    it "should allow custom run_at arguments" do
      run_at = 1.hour.from_now
      expect(TomQueue::Enqueue::Publish.queue_manager).to receive(:publish).with(payload, run_at: run_at, priority: TomQueue::NORMAL_PRIORITY).once
      instance.call(job, run_at: run_at)
    end

    it "should skip the publish if the skip_publish flag is set" do
      expect(TomQueue::Enqueue::Publish.queue_manager).not_to receive(:publish)
      job.skip_publish = true
      instance.call(job, {})
    end
  end
end
