require "tom_queue/helper"

describe TomQueue::Persistence::Model do
  class ModelTestJob
    def perform
      # noop
    end
  end

  describe ".republish_all" do
    it "should push all jobs onto AMQP" do
      TomQueue::Persistence::Model.delete_all
      expect(TomQueue::Enqueue::Publish.queue_manager).to receive(:publish).exactly(5).times
      5.times { TomQueue::Persistence::Model.create!(payload_object: ModelTestJob.new) }
      TomQueue::Persistence::Model.republish_all
    end
  end

  describe "#republish" do
    let(:instance) { TomQueue::Persistence::Model.create!(payload_object: ModelTestJob.new) }

    it "should push the job onto AMQP" do
      expect(TomQueue::Enqueue::Publish.queue_manager).to receive(:publish).once
      instance.republish
    end
  end
end
