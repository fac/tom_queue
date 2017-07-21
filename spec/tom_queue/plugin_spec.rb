require "tom_queue/helper"

describe TomQueue::Plugin do
  let(:fake_lifecycle) { TomQueue::Lifecycle.new }
  let(:fake_worker) { instance_double("TomQueue::Worker") }
  let(:fake_job) { instance_double("TomQueue::Persistence::Model") }

  class PluginTestPlugin < TomQueue::Plugin
    cattr_accessor :fired

    callbacks do |lifecycle|
      lifecycle.before(:execute) { |worker| fired << [lifecycle, :before_execute, worker] }
      lifecycle.after(:invoke_job) { |job| fired << [lifecycle, :invoke_job, job] }
    end
  end

  it "should hook in to the lifecycle events" do
    PluginTestPlugin.new(fake_lifecycle)

    PluginTestPlugin.fired = []
    fake_lifecycle.run_callbacks(:execute, fake_worker) { }
    expect(PluginTestPlugin.fired.length).to eq(1)
    expect(PluginTestPlugin.fired[0]).to eq([fake_lifecycle, :before_execute, fake_worker])
  end
end
