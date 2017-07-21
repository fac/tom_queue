require "spec_helper"

describe "Setup" do
  specify "Sanity Check - Bunny should be available" do
    expect { Bunny.new(AMQP_CONFIG).start }.not_to raise_error
  end
end
