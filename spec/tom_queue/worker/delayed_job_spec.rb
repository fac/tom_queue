require "tom_queue/helper"

describe TomQueue::Worker::DelayedJob do
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
  let(:instance) { TomQueue::Worker::DelayedJob.new(chain) }
  let(:options) { { work: work, worker: worker } }

  describe "for a non-job payload" do
    let(:payload) { JSON.dump({"foo" => "bar"})}

    it "should skip the layer" do
      expect(chain).to receive(:call).with(options)
      instance.call(options)
    end
  end

  describe "for a non-JSON work payload" do
    let(:payload) { "FooBar" }

    it "should raise a DeserializationError" do
      expect { instance.call(options) }.to raise_error(
        TomQueue::DeserializationError,
        /Failed to parse JSON payload/
      )
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(options) rescue nil
    end
  end

  describe "for a job which is successfully invoked" do
    let(:chain) {
      lambda do |options|
        job = options[:job]
        expect(job).to be_locked
        expect(job).not_to be_changed
        expect(job.locked_by).to eq(worker.name)
        options
      end
    }

    it "should lock the job record and pass into the chain" do
      expect(chain).to receive(:call).
        with(instance_of(Hash)).
        and_call_original

      expect(job.reload).not_to be_locked
      instance.call(options)
    end

    it "should destroy the job record" do
      instance.call(options)
      expect(TomQueue::Persistence::Model.find_by(id: job.id)).to be_nil
    end


  end

  describe "for an job whose payload raises an exception" do
    let(:chain) {
      lambda do |options|
        job = options[:job]
        expect(job).to be_locked
        expect(job).not_to be_changed
        expect(job.locked_by).to eq(worker.name)
        raise RuntimeError, "Spit Happens"
      end
    }

    it "should lock the job record (see lambda in :chain) and pass into the chain" do
      expect(chain).to receive(:call).
        with(instance_of(Hash)).
        and_call_original

      expect { instance.call(options) }.to raise_error(TomQueue::RepublishableError)
    end

    it "should set last_error on the record" do
      instance.call(options) rescue nil
      expect(job.reload.last_error).to match(/Spit Happens/)
    end

    it "should unlock the record" do
      instance.call(options) rescue nil
      expect(job.reload).not_to be_locked
    end
  end

  describe "notification for a non-existent (completed) job" do
    let(:payload) {
      JSON.dump({
        "delayed_job_id" => -1,
        "delayed_job_digest" => "foo",
        "delayed_job_updated_at" => Time.now.iso8601(0)
      })
    }

    it "should raise a NotFoundError" do
      expect { instance.call(options) }.to raise_error(
        TomQueue::DelayedJob::NotFoundError,
        /Received notification for non-existent job -1/
      )
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(options) rescue nil
    end
  end

  describe "notification for a failed job" do
    let(:job) { TomQueue::Persistence::Model.create!(failed_at: Time.now, payload_object: payload_object) }

    it "should raise a FailedError" do
      expect { instance.call(options) }.to raise_error(
        TomQueue::DelayedJob::FailedError,
        /Received notification for failed job #{job.id}/
      )
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(options) rescue nil
    end
  end

  describe "notification for a locked job" do
    let(:job) { TomQueue::Persistence::Model.create!(locked_at: Time.now, locked_by: "Foo", payload_object: payload_object) }

    it "should raise a LockedError" do
      expect { instance.call(options) }.to raise_error(
        TomQueue::DelayedJob::LockedError,
        /Received notification for locked job #{job.id}/
      )
    end

    it "should not call the chain" do
      expect(chain).not_to receive(:call)
      instance.call(options) rescue nil
    end
  end
end
