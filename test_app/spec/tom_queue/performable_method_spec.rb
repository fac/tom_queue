require "spec_helper"

describe "PerformableMethod", worker: true do
  class WorkUnit
    def do_something
      TomQueue.test_logger.debug("RUNNING: WorkUnit#do_something")
    end
  end

  it "should execute immediately" do
    expect { WorkUnit.new.delay.do_something }.not_to raise_error
    wait(1.second).for { message("RUNNING: WorkUnit#do_something") }.to be_truthy
  end
end
