require 'tom_queue/helper'

describe TomQueue::DeferredWorkManager

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

    it "should raise an argument error if the :run_at option isn't specified"
    it "should raise an argument if the work isn't a string"
  end

end
