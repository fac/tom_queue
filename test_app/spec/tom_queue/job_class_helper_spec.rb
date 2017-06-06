require "spec_helper"

describe "Job Class Helper" do
  it "should create a new class each call" do
    foo = job_class
    bar = job_class

    expect(foo).not_to eq(bar)
  end

  it "should allow multiple classes to be tracked" do
    foo = job_class
    bar = job_class

    expect(foo).not_to be_completed
    expect(bar).not_to be_completed

    foo.new.perform

    expect(foo).to be_completed
    expect(bar).not_to be_completed
  end

  it "should allow jobs to be tracked in different processes" do
    foo = job_class

    begin
      pid = fork do
        foo.new.perform
      end

      sleep(0.1)

      expect(foo).to be_completed

    ensure
      Process.kill("KILL", pid)
    end
  end
end
