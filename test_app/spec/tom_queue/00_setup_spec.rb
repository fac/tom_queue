require "spec_helper"

describe "Setup" do
  specify "Sanity Check - Bunny should be available" do
    expect { Bunny.new(AMQP_CONFIG).start }.not_to raise_error
  end

  specify "TomQueue should be configured as the backend for Delayed Job" do
    expect(Delayed::Worker.backend).to eq(TomQueue::DelayedJob::Job)
  end
end
