require 'tom_queue/helper'

describe TomQueue::DeferredWorkSet do
  let(:set) { TomQueue::DeferredWorkSet.new }

  it "should be creatable" do
    set.should be_a(TomQueue::DeferredWorkSet)
  end

  it "should allow work to be scheduled" do
    set.schedule(Time.now + 0.2, "something")
    set.schedule(Time.now + 0.3, "else")
    set.size.should == 2
  end

  describe "earliest" do

    it "should return nil if there is no work in the set" do
      set.earliest.should be_nil
    end

    it "should return the only item if there is one item in the set" do
      work = mock("Work")
      set.schedule( Time.now + 0.3, work)
      set.earliest.should == work
    end

    it "should return the item in the set with the lowest run_at value" do
      set.schedule( Time.now + 0.2, work1 = mock("Work") )
      set.schedule( Time.now + 0.1, work2 = mock("Work") )
      set.schedule( Time.now + 0.3, work3 = mock("Work") )
      set.earliest.should == work2
    end

  end

  describe "sleep" do

    it "should block for the timeout value if there is no work in the queue" do
      start_time = Time.now
      set.sleep(0.1)
      Time.now.should > start_time + 0.1
    end

    it "should block until the earliest work in the set" do
      start_time = Time.now
      set.schedule(start_time + 1.5, "work")
      set.schedule(start_time + 0.1, "work")
      set.sleep(10)
      Time.now.should > start_time + 0.1
      Time.now.should < start_time + 0.2
    end

    it "should return immediately if it is interrupted by an external thread" do
      Thread.new { sleep 0.1; set.interrupt }
      start_time = Time.now
      set.schedule(start_time + 1.5, "work")
      set.schedule(start_time + 5, "work")
      set.sleep(10)
      Time.now.should > start_time + 0.1
      Time.now.should < start_time + 0.2
    end

    it "should block until the earliest work, even if earlier work is added after the block" do
      start_time = Time.now
      Thread.new do
        sleep 0.1
        set.schedule(start_time + 0.2, "early")
      end
      set.schedule(start_time + 1.5, "late")
      set.sleep(10)
      Time.now.should > start_time + 0.2
      Time.now.should < start_time + 0.3

    end

  end

end