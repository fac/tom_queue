require 'tom_queue/helper'

describe TomQueue::DeferredWorkManager do

  let(:queue_manager) { TomQueue::QueueManager.new('fa.test')}
  let(:manager) { TomQueue::DeferredWorkManager.new('fa.test', queue_manager)}

  describe "creation" do  
    it "should be created with a prefix" do
      manager.prefix.should == 'fa.test'
    end
    it "should be created with a delegate" do
      manager.delegate.should == queue_manager
    end
  end

  describe "handle_deferred(work, opts)" do

    it "should raise an argument error if the :run_at option isn't specified" do
      lambda {
        manager.handle_deferred("work", {})
      }.should raise_exception(ArgumentError, /:run_at must be specified/)
    end
    it "should raise an argument error if the :run_at isn't a ruby time" do
      lambda {
        manager.handle_deferred("work", {:run_at => "in about half an hour"})
      }.should raise_exception(ArgumentError, /:run_at must be a Time object/)
    end
    it "should raise an argument error if the work isn't a string" do
      lambda {
        manager.handle_deferred({"foo" => :bar}, {:run_at => Time.now})
      }.should raise_exception(ArgumentError, /work must be a string/)
    end
  end

end
