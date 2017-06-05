require "spec_helper"

describe TomQueue do
  it "should be configured as the backend for Delayed Job" do
    expect(Delayed::Worker.backend).to eq(TomQueue::DelayedJob::Job)
  end
end
