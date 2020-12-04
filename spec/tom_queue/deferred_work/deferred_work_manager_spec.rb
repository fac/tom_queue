require "spec_helper"

describe TomQueue::DeferredWorkManager do
  describe "DeferredWorkManager.new" do
    subject { TomQueue::DeferredWorkManager.new }

    it { should respond_to :deferred_set }
    it { should respond_to :out_manager }

    it "should use the default prefix if none is provided" do
      TomQueue.default_prefix = 'default.prefix'
      expect(TomQueue::DeferredWorkManager.new.prefix).to eq 'default.prefix'
    end

    it "should raise an exception if no prefix is provided and default isn't set" do
      TomQueue.default_prefix = nil
      expect {
        TomQueue::DeferredWorkManager.new
      }.to raise_exception(ArgumentError, 'prefix is required')
    end

    it "should notify something if process crashes" do
      TomQueue.exception_reporter = double("ExceptionReporter", :notify => nil)
      subject.out_manager.publish("work", :run_at => Time.now + 5)
      subject.deferred_set.should_receive(:pop).and_raise(RuntimeError, "Yaks Everywhere!")
      TomQueue.exception_reporter.should_receive(:notify) do |exception|
        exception.should be_a(RuntimeError)
        exception.message.should == "Yaks Everywhere!"
      end
      subject.start
    end

    it "should notify something if consumer thread crashes and re-queue message once" do
      TomQueue.exception_reporter = double("ExceptionReporter", :notify => nil)
      subject.deferred_set.should_receive(:schedule).twice.and_raise(RuntimeError, "Yaks Everywhere!")
      TomQueue.exception_reporter.should_receive(:notify) do |exception|
        exception.should be_a(RuntimeError)
        exception.message.should == "Yaks Everywhere!"
      end

      subject.out_manager.publish("work", :run_at => Time.now + 5)
      Timeout.timeout(1) {subject.start} rescue nil
    end
  end
end
