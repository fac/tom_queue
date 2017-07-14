require "tom_queue/helper"

describe TomQueue::Worker::ErrorHandling do
  let(:instance) { TomQueue::Worker::ErrorHandling.new(chain) }

  describe "when the stack raises a PermanentError" do
    let(:chain) { lambda { raise TomQueue::PermanentError, "Spit Happens" } }

    it "should log the error message" do
      expect(TomQueue.logger).to receive(:warn).with("Spit Happens").once
      instance.call()
    end

    it "should swallow the exception" do
      expect { instance.call() }.not_to raise_error
    end

    it "should not attempt to requeue the work" do
      expect(TomQueue::Worker::ErrorHandling).not_to receive(:republish).with(any_args)
      instance.call()
    end
  end

  describe "when the stack raises a RetryableError" do
    let(:work) { JSON.dump("delayed_job_id" => 1, "delayed_job_digest" => "foo")}
    let(:chain) { lambda { raise TomQueue::RetryableError.new("Spit Happens", work: work) } }

    it "should log the error message" do
      expect(TomQueue.logger).to receive(:warn).with("Spit Happens").once
      instance.call()
    end

    it "should swallow the exception" do
      expect { instance.call() }.not_to raise_error
    end

    it "should not requeue the work" do
      expect(TomQueue::Worker::ErrorHandling).not_to receive(:republish)
      instance.call()
    end
  end

  describe "when the stack raises an unknown error" do
    let(:chain) { lambda { raise RuntimeError, "Spit Happens" } }

    it "should log the error message" do
      expect(TomQueue.logger).to receive(:error).with("Spit Happens").once
      instance.call()
    end

    it "should swallow the exception" do
      expect { instance.call() }.not_to raise_error
    end

    it "should send the exception to the exception reporter" do
      expect(TomQueue.exception_reporter).to receive(:notify).with(instance_of(RuntimeError)).once
      instance.call()
    end

    it "should not attempt to requeue the work" do
      expect(TomQueue::Worker::ErrorHandling).not_to receive(:republish).with(any_args)
      instance.call()
    end
  end

  describe "when the stack raises a RepublishableError" do
    let(:work) { JSON.dump("delayed_job_id" => 1, "delayed_job_digest" => "foo")}
    let(:chain) { lambda { raise TomQueue::RepublishableError.new("Spit Happens", work: work) } }

    before do
      allow(TomQueue::Worker::ErrorHandling).to receive(:republish).with(any_args)
    end

    it "should log the error message" do
      expect(TomQueue.logger).to receive(:warn).with("Spit Happens").once
      instance.call()
    end

    it "should swallow the exception" do
      expect { instance.call() }.not_to raise_error
    end

    it "should requeue the work" do
      expect(TomQueue::Worker::ErrorHandling).to receive(:republish).with(instance_of(TomQueue::RepublishableError)).once
      instance.call()
    end
  end

  describe ".republish" do

  end
end
