require "tom_queue/helper"

describe TomQueue::Lifecycle do
  let(:instance) { TomQueue::Lifecycle.new }
  let(:fake_job) { instance_double("TomQueue::Persistence::Model") }
  let(:fake_worker) { instance_double("TomQueue::Worker") }

  it "should fire the relevant callbacks in order" do
    fired = []
    before = false
    after = false
    around = nil

    instance.before(:execute) do |worker|
      expect(worker).to eq(fake_worker)
      fired << :before
    end

    instance.around(:execute) do |worker, &block|
      expect(worker).to eq(fake_worker)
      fired << :around_before
      block.call
      fired << :around_after
    end

    instance.after(:execute) do |worker|
      expect(worker).to eq(fake_worker)
      fired << :after
    end

    instance.run_callbacks(:execute, fake_worker) do
      expect(fired).to eq([:before, :around_before])
    end
    expect(fired).to eq([:before, :around_before, :around_after, :after])
  end

  it "should only fire the callbacks for the given event" do
    fired = []
    instance.before(:execute) { |worker| fired << :execute }
    instance.before(:perform) do |worker, job|
      expect(worker).to eq(fake_worker)
      expect(job).to eq(fake_job)
      fired << :perform
    end

    instance.run_callbacks(:perform, fake_worker, fake_job) { }

    expect(fired).to eq([:perform])
  end
end
