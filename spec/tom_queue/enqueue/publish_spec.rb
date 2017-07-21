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

  describe "with ActiveRecord transactions" do
    before do
      TomQueue::Enqueue::Publish.uncommitted.clear
    end

    it "should not publish until all transactions are complete" do
      allow(TomQueue::Enqueue::Publish.queue_manager).to receive(:publish).and_return(nil)
      publish_args = nil # define outwith the transaction...

      ActiveRecord::Base.transaction do
        job = TomQueue::Persistence::Model.create!(payload_object: TestJob.new)
        expect { instance.call(job, {}) }.to change { TomQueue::Enqueue::Publish.uncommitted.length }.by(1)
        expect(TomQueue::Enqueue::Publish.queue_manager).not_to have_received(:publish)
        publish_args = TomQueue::Enqueue::Publish.uncommitted.first
      end

      wait(1.second).for { TomQueue::Enqueue::Publish.uncommitted.length }.to eq(0)
      expect(publish_args).not_to be_nil
      expect(TomQueue::Enqueue::Publish.queue_manager).to have_received(:publish).with(*publish_args)
    end

    it "should clear the uncommitted messages without publishing after a rollback" do
      expect(TomQueue::Enqueue::Publish.queue_manager).not_to receive(:publish)

      begin
        ActiveRecord::Base.transaction do
          job = TomQueue::Persistence::Model.create!(payload_object: TestJob.new)
          expect { instance.call(job, {}) }.to change { TomQueue::Enqueue::Publish.uncommitted.length }.by(1)
          raise "Boom"
        end
      rescue
      end

      expect(TomQueue::Enqueue::Publish.uncommitted.length).to eq(0)
    end
  end
end
