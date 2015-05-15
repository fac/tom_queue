require 'tom_queue/base_helper'
require 'tom_queue/delayed_job'

describe Delayed::Job, "integration detection spec", :timeout => 10 do

  it "detects when the hook has not been applied" do
    expect(TomQueue.active?).to be false
  end

  it "detects when the hook has been applied" do
    TomQueue::DelayedJob.apply_hook!
    expect(TomQueue.active?).to be true
  end

end
