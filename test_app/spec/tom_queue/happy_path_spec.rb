require "spec_helper"

describe "Job Queueing" do
  SimpleJob = Struct.new(:id) do
    def perform
      # noop
    end
  end

  it "should send the job id to AMQP" do
    expect { Delayed::Job.enqueue(SimpleJob.new(123)) }.to change { queue(:normal)["messages"] }.by(1)
  end

  it "should store the payload in Delayed::Job" do
    expect { Delayed::Job.enqueue(SimpleJob.new(123)) }.to change { Delayed::Job.count }.by(1)
    job = Delayed::Job.last
    expect(YAML.load(job.handler)).to be_a(SimpleJob)
  end

  it "should execute the payload when running" do
    with_worker do |worker|
      Delayed::Job.enqueue(SimpleJob.new(123))

    end
  end

  it "should remove the job from Delayed::Job once run" do
    with_worker do |worker|
      expect { Delayed::Job.enqueue(SimpleJob.new(123)) }.to change { Delayed::Job.count }.by(1)
      job = Delayed::Job.last
      expect { worker.step }.to change { Delayed::Job.count }.by(-1)
      expect(Delayed::Job.where(id: job.id).first).to be_nil
    end
  end
end
