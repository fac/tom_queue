require "tom_queue/helper"

describe TomQueue::Layers::JobLocking do
  class TestJob
    def perform
      true
    end
  end

  let(:payload_object) { TestJob.new.to_yaml }
  let(:job) { TomQueue::Persistence::Model.create!(payload_object: payload_object) }
  let(:payload) {
    JSON.dump({
      "delayed_job_id" => job.id,
      "delayed_job_digest" => job.digest,
      "delayed_job_updated_at" => job.updated_at.iso8601(0)
    })
  }
  let(:worker) { TomQueue::Worker.new }
  let(:work) { double(TomQueue::Work, payload: payload, ack!: true) }
  let(:chain) { lambda { |work, options| [work, options] } }
  let(:instance) { TomQueue::Layers::JobLocking.new(chain) }

  describe "for a non-job payload" do
    let(:payload) { JSON.dump({"foo" => "bar"})}

    it "should skip the layer" do
      expect(chain).to receive(:call).with(work, {})
      instance.call(work, {})
    end
  end

  describe "for a non-JSON work payload" do
    let(:payload) { "FooBar" }

    it "should ack! the work" do
      expect(work).to receive(:ack!)
      instance.call(work, { worker: worker })
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(work, { worker: worker })
    end

    it "should log the situation" do
      expect(TomQueue.logger).to receive(:error).with(/Failed to parse JSON payload/)
      instance.call(work, { worker: worker })
    end
  end

  describe "for a successfully invoked job payload" do
    let(:chain) {
      lambda do |job, options|
        expect(job).to be_locked
        expect(job).not_to be_changed
        expect(job.locked_by).to eq(worker.name)
        [job, options.merge(result: true)]
      end
    }

    it "should lock the job record and pass into the chain" do
      expect(chain).to receive(:call).
        with(instance_of(TomQueue::Persistence::Model), instance_of(Hash)).
        and_call_original

      expect(job.reload).not_to be_locked
      instance.call(work, { worker: worker })
    end
  end

  describe "for a failing job payload" do
    let(:chain) {
      lambda do |job, options|
        expect(job).to be_locked
        expect(job).not_to be_changed
        expect(job.locked_by).to eq(worker.name)
        [job, options.merge(result: false)]
      end
    }

    it "should lock the job record and pass into the chain" do
      expect(chain).to receive(:call).
        with(instance_of(TomQueue::Persistence::Model), instance_of(Hash)).
        and_call_original

      expect(job.reload).not_to be_locked
      instance.call(work, { worker: worker })
    end
  end

  describe "for an exceptional job payload" do
    let(:chain) {
      lambda do |job, options|
        expect(job).to be_locked
        expect(job).not_to be_changed
        expect(job.locked_by).to eq(worker.name)
        raise RuntimeError
      end
    }

    it "should lock the job record and pass into the chain" do
      expect(chain).to receive(:call).
        with(instance_of(TomQueue::Persistence::Model), instance_of(Hash)).
        and_call_original

      expect(job.reload).not_to be_locked
      expect { instance.call(work, { worker: worker }) }.to raise_error(RuntimeError)
    end
  end

  describe "for a non-existent (completed) job" do
    let(:payload) {
      JSON.dump({
        "delayed_job_id" => -1,
        "delayed_job_digest" => "foo",
        "delayed_job_updated_at" => Time.now.iso8601(0)
      })
    }

    it "should ack! the work" do
      expect(work).to receive(:ack!)
      instance.call(work, { worker: worker })
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(work, { worker: worker })
    end

    it "should log the situation" do
      expect(TomQueue.logger).to receive(:warn).with(/Received notification for non-existent job -1/)
      instance.call(work, { worker: worker })
    end
  end

  describe "for a failed job" do
    let(:job) { TomQueue::Persistence::Model.create!(failed_at: Time.now, payload_object: payload_object) }

    it "should ack! the work" do
      expect(work).to receive(:ack!)
      instance.call(work, { worker: worker })
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(work, { worker: worker })
    end

    it "should log the situation" do
      expect(TomQueue.logger).to receive(:warn).with(/Received notification for failed job #{job.id}/)
      instance.call(work, { worker: worker })
    end
  end

  describe "for a locked job" do
    let(:job) { TomQueue::Persistence::Model.create!(locked_at: Time.now, locked_by: "Foo", payload_object: payload_object) }

    it "should ack! the work" do
      expect(work).to receive(:ack!)
      instance.call(work, { worker: worker })
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(work, { worker: worker })
    end

    it "should log the situation" do
      expect(TomQueue.logger).to receive(:warn).with(/Received notification for locked job #{job.id}/)
      instance.call(work, { worker: worker })
    end
  end
end
