require "tom_queue/helper"

describe TomQueue::Worker::Stack do
  class JobClass
    def perform
      raise "woo"
    end
  end

  before do
    TomQueue.handlers.clear
  end

  let(:job) { TomQueue::Persistence::Model.create!(payload_object: JobClass.new) }
  let(:payload) { job.payload }
  let(:stack) { TomQueue::Worker::Stack }
  let(:work) { instance_double("TomQueue::Work", payload: payload, ack!: true, nack!: true) }
  let(:worker) { TomQueue::Worker.new }

  it "should run the stack" do
    allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
    expect { stack.call(worker: worker) }.not_to raise_error
  end
end
