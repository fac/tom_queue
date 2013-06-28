require 'tom_queue/helper'

describe TomQueue::DeferredWorkManager do


  describe "DeferredWorkManager.instance - singleton accessor" do

    it "should return a DelayedWorkManager instance" do
      TomQueue::DeferredWorkManager.instance('some.prefix').should be_a(TomQueue::DeferredWorkManager)
    end

    it "should use the default prefix if none is provided" do
      TomQueue.default_prefix = 'default.prefix'
      TomQueue::DeferredWorkManager.instance.prefix.should == 'default.prefix'
    end

    it "should raise an exception if no prefix is provided and default isn't set" do
      TomQueue.default_prefix = nil
      lambda {
        TomQueue::DeferredWorkManager.instance
      }.should raise_exception(ArgumentError, 'prefix is required')
    end

    it "should return the same object for the same prefix" do
      TomQueue::DeferredWorkManager.instance('some.prefix').should == TomQueue::DeferredWorkManager.instance('some.prefix')
      TomQueue::DeferredWorkManager.instance('another.prefix').should == TomQueue::DeferredWorkManager.instance('another.prefix')
    end

    it "should return a different object for different prefixes" do
      TomQueue::DeferredWorkManager.instance('some.prefix').should_not == TomQueue::DeferredWorkManager.instance('another.prefix')
    end
    it "should set the prefix for the instance created" do
      TomQueue::DeferredWorkManager.instance('some.prefix').prefix.should == 'some.prefix'
      TomQueue::DeferredWorkManager.instance('another.prefix').prefix.should == 'another.prefix'
    end
  end

  describe "for testing - DeferredWorkManager.reset! method" do

    it "should return nil" do
      TomQueue::DeferredWorkManager.reset!.should be_nil
    end

    it "should cleared the singleton instances" do
      first_singleton = TomQueue::DeferredWorkManager.instance('prefix')
      TomQueue::DeferredWorkManager.reset!
      TomQueue::DeferredWorkManager.instance('prefix').should_not == first_singleton
    end
  end



  # let(:queue_manager) { TomQueue::QueueManager.new('fa.test')}
  # let(:manager) { TomQueue::DeferredWorkManager.new('fa.test', queue_manager)}

  # before do
  #   manager.purge!
  # end

  # describe "creation" do  
  #   it "should be created with a prefix" do
  #     manager.prefix.should == 'fa.test'
  #   end
  #   it "should be created with a delegate" do
  #     manager.delegate.should == queue_manager
  #   end
  # end

  # describe "handle_deferred(work, opts)" do

  #   it "should raise an argument error if the :run_at option isn't specified" do
  #     lambda {
  #       manager.handle_deferred("work", {})
  #     }.should raise_exception(ArgumentError, /:run_at must be specified/)
  #   end
  #   it "should raise an argument error if the :run_at isn't a ruby time" do
  #     lambda {
  #       manager.handle_deferred("work", {:run_at => "in about half an hour"})
  #     }.should raise_exception(ArgumentError, /:run_at must be a Time object/)
  #   end
  #   it "should raise an argument error if the work isn't a string" do
  #     lambda {
  #       manager.handle_deferred({"foo" => :bar}, {:run_at => Time.now})
  #     }.should raise_exception(ArgumentError, /work must be a string/)
  #   end
  # end

end
