require "spec_helper"

describe "Successful job", worker: true do
  let(:payload) { TestJob.new("Foo") }

  it "should run the job immediately" do
    Delayed::Job.enqueue(payload)
    wait(1.second).for { message("RUNNING: Foo") }
  end

  it "should clean up the database once run" do
    job = Delayed::Job.enqueue(payload)
    expect(Delayed::Job.where(id: job.id).first).to be_present
    wait(1.second).for { message("RUNNING: Foo") }
    wait(1.second).for { Delayed::Job.where(id: job.id).first }.to be_nil
  end

  it "should not run a job scheduled for the future immediately" do
    Delayed::Job.enqueue(payload, run_at: 1.minute.from_now)
    expect(message("RUNNING: Foo", 1.second)).to be_falsy
  end

  it "should fire hooks in the correct order" do
    Delayed::Job.enqueue(payload)
    messages = worker_messages(4)
    expect(messages[0]).to match("BEFORE_HOOK: Foo")
    expect(messages[1]).to match("RUNNING: Foo")
    expect(messages[2]).to match("SUCCESS_HOOK: Foo")
    expect(messages[3]).to match("AFTER_HOOK: Foo")
  end
end
