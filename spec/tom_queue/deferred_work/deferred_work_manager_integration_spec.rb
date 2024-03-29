require "spec_helper"

# "Integration" For lack of a better word, trying to simulate various failures

describe "DeferredWorkManager", "#stop" do
  class ExceptionReporter
    attr_reader :filepath

    def initialize(filepath)
      @filepath = filepath
    end

    def notify(exception)
      File.open(filepath, "w+") { |file| file.write(exception) }
    end
  end

  let!(:exception_reporter) { ExceptionReporter.new(file.path) }

  let!(:file) { Tempfile.new("exception") }
  let!(:worker_process) do
    msg = ChildProcessMessage.new
    TestForkedProcess.start do
      TomQueue.bunny = Bunny.new(TEST_AMQP_CONFIG)
      TomQueue.bunny.start
      TomQueue.exception_reporter = exception_reporter
      manager = TomQueue::DeferredWorkManager.new(TomQueue.default_prefix)

      manager.start { msg.set("started") }
    end.tap { |_| msg.wait }
  end

  subject do
    worker_process.term
    @status = worker_process.join(timeout: 2)
  end

  it "handles SIGTERM send by god properly" do
    subject
    expect(@status.exitstatus).to eq 0
  end

  it "doesn't report into the exception_reporter" do
    subject
    expect(file.size).to eq 0
  end
end

describe "DeferredWorkManager integration scenarios"  do
  it "should restore un-acked messages when the process has crashed" do
    @prefix = "test-#{Time.now.to_f}"

    process = TestForkedProcess.start do
      TomQueue.bunny = Bunny.new(TEST_AMQP_CONFIG)
      TomQueue.bunny.start
      @manager = TomQueue::DeferredWorkManager.new(@prefix)
      TomQueue.exception_reporter = double("ExceptionReporter", :notify => nil)
      @manager.out_manager.publish("work", :run_at => Time.now + 5)
      @manager.deferred_set.should_receive(:pop).and_raise(RuntimeError, "Yaks Everywhere!")
      @manager.start
    end

    process.join(timeout: 2)

    # we would expect the message to be on the queue again, so this
    # should "just work"
    ch = TomQueue.bunny.create_channel
    ch.queue("#{@prefix}.work.deferred", durable: true).pop.last.should == "work"
  end

  describe "with a deferred work set process", timeout: 4 do
    let(:ack_timeout) { 10.minutes }
    after do
      class TomQueue::DeferredWorkSet
        if method_defined?(:orig_schedule)
          undef_method :schedule
          alias_method :schedule, :orig_schedule
        end
      end

      @process.kill
      @process.join(timeout: 2)
    end

    before do
      @prefix = "test-#{Time.now.to_f}"

      @process = TestForkedProcess.start do
        TomQueue.exception_reporter = nil
        require 'tom_queue/deferred_work_set'

        # Look away...
        class TomQueue::DeferredWorkSet

          unless method_defined?(:orig_schedule)
            def new_schedule(run_at, message)
              raise RuntimeError, "ENOHAIR" if message.last == "explosive"
              orig_schedule(run_at, message)
            end
          end
          alias_method :orig_schedule, :schedule
          alias_method :schedule, :new_schedule
        end

        TomQueue.bunny = Bunny.new(TEST_AMQP_CONFIG)
        TomQueue.bunny.start
        @manager = TomQueue::DeferredWorkManager.new(@prefix, ack_timeout)

        @manager.start
      end
      @queue_manager = TomQueue::QueueManager.new(@prefix)
      @queue_manager.start_consumers!
    end

    describe "if the AMQP consumer thread crashes", timeout: 4 do
      let(:crash!) do
        @queue_manager.publish("explosive", :run_at => Time.now + 2)
      end

      it "should work around the broken messages" do
        @queue_manager.publish("foo", :run_at => Time.now + 1)
        crash!
        @queue_manager.publish("bar", :run_at => Time.now + 2)

        @queue_manager.pop.ack!.payload.should == "foo"
        @queue_manager.pop.ack!.payload.should == "bar"
      end

      it "should re-queue the message once" do
        crash!
        @queue_manager.publish("bar", :run_at => Time.now + 1)
        @queue_manager.pop.ack!
      end
    end

    describe "with a short ack timeout" do
      let(:ack_timeout) { 1.second }

      it "acks the message within the timeout" do
        @queue_manager.publish("foo", :run_at => Time.now + 1000000)
        @queue_manager.pop.ack!.payload.should == "foo"
      end
    end
  end
end
