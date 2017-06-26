require "tom_queue/helper"

describe TomQueue::Worker::Pop do
  class TestJob
    cattr_accessor :complete

    def perform
      self.class.complete = true
    end
  end

  let(:worker) { TomQueue::Worker.new }

  around do |example|
    clear_queues
    example.call
    clear_queues
  end

  describe "Pop.pop" do
    it "should retrieve a work unit from the queue" do
      publish_job
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
    let(:chain) { lambda { |work, options| [work, options] } }
    let(:instance) { TomQueue::Worker::Pop.new(chain) }
    let(:work) { instance_double("TomQueue::Work", ack!: true, nack!: true) }

    it "should call the next layer in the stack if work is available" do
      expect(chain).to receive(:call).with(work, {}).and_return([true, {work: work}])
      allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      instance.call(:bar, {})
    end

    it "should ack! the work" do
      expect(work).to receive(:ack!)
      allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      instance.call(:bar, {})
    end

    it "should return without calling the next layer if no work is available" do
      expect(chain).not_to receive(:call)
      allow(TomQueue::Worker::Pop).to receive(:pop).and_return(nil)
      expect(instance.call(:bar, {})).to eq([false, {}])
    end

    describe "SignalException" do
      before do
        allow(chain).to receive(:call).and_raise(SignalException, :KILL)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should nack! the work and return" do
        expect(work).to receive(:nack!)
        expect(instance.call(:foo, {})).to eq([false, {work: work}])
      end
    end

    describe "unhandled exceptions" do
      before do
        allow(chain).to receive(:call).and_raise(RuntimeError)
        allow(TomQueue::Worker::Pop).to receive(:pop).and_return(work)
      end

      it "should nack! the work and raise" do
        expect(work).to receive(:nack!)
        expect { instance.call(:foo, {}) }.to raise_error(RuntimeError)
      end
    end
  end

  private

  def clear_queue(priority)
    RestClient.delete("http://guest:guest@localhost:15672/api/queues/test/#{TomQueue.default_prefix}.balance.#{priority}")
  rescue
  end

  def clear_queues
    TomQueue::PRIORITIES.each(&method(:clear_queue))
  end

  def publish_job
    job = TomQueue::Persistence::Model.create!(payload_object: TestJob.new)
    TomQueue::Enqueue::Publish.new.call(job, {})
  end
end
