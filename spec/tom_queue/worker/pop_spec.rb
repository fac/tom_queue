require "tom_queue/helper"

describe TomQueue::Worker::Pop do
  class TestJob
    cattr_accessor :complete

    def perform
      self.class.complete = true
    end
  end

  let(:worker) { TomQueue::Worker.new }

  describe "Pop.pop" do
    let(:job) { TomQueue::Persistence::Model.create!(payload_object: TestJob.new) }

    it "should retrieve a work unit from the queue" do
      TomQueue::Enqueue::Publish.new.call(job, {})
      result = TomQueue::Worker::Pop.pop(worker)
      expect(result).to be_a(TomQueue::Work)
    end

    it "should block if the queue is empty" do
      expect {
        Timeout.timeout(1.0) { TomQueue::Worker::Pop.pop(worker) }
      }.to raise_error(Timeout::Error)
    end
  end

  describe "Pop#call" do
    let(:chain) { lambda { |options| options } }
    let(:instance) { TomQueue::Worker::Pop.new(chain) }
    let(:work) { instance_double("TomQueue::Work", ack!: true, nack!: true) }

    it "should call the next layer in the stack if work is available" do
      expect(chain).to receive(:call).with(work: work)
      allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      instance.call({})
    end

    it "should ack! the work" do
      expect(work).to receive(:ack!)
      allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      instance.call({})
    end

    it "should return without calling the next layer if no work is available" do
      expect(chain).not_to receive(:call)
      allow(TomQueue::Worker::Pop).to receive(:pop).and_return(nil)
      instance.call({})
    end

    describe "when a SignalException is raised" do
      before do
        allow(chain).to receive(:call).and_raise(SignalException, :KILL)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should nack! the work" do
        expect(work).to receive(:nack!)
        instance.call({}) rescue nil
      end

      it "should raise a RetryableError" do
        expect { instance.call({}) }.to raise_error(TomQueue::RetryableError)
      end
    end

    describe "when a PermanentError is raised" do
      let(:ex) { TomQueue::PermanentError.new("Spit Happens") }

      before do
        allow(chain).to receive(:call).and_raise(ex)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should ack! the work" do
        expect(work).to receive(:ack!)
        instance.call({}) rescue nil
      end

      it "should raise the error" do
        expect { instance.call({}) }.to raise_error(ex)
      end
    end

    describe "when a RepublishableError is raised" do
      let(:ex) { TomQueue::RepublishableError.new("Spit Happens") }

      before do
        allow(chain).to receive(:call).and_raise(ex)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should ack! the work" do
        expect(work).to receive(:ack!)
        instance.call({}) rescue nil
      end

      it "should raise the error" do
        expect { instance.call({}) }.to raise_error(ex)
      end
    end

    describe "when a RetryableError is raised" do
      let(:ex) { TomQueue::RetryableError.new("Spit Happens") }

      before do
        allow(chain).to receive(:call).and_raise(ex)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should nack! the work" do
        expect(work).to receive(:nack!)
        instance.call({}) rescue nil
      end

      it "should raise the error" do
        expect { instance.call({}) }.to raise_error(ex)
      end
    end

    describe "when an unknown Exception is raised" do
      before do
        allow(chain).to receive(:call).and_raise(RuntimeError)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should nack! the work" do
        expect(work).to receive(:nack!)
        instance.call({}) rescue nil
      end

      it "should raise the error" do
        expect { instance.call({}) }.to raise_error(RuntimeError)
      end
    end
  end
end
