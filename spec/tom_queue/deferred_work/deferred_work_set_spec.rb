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
      work = double("Work")
      set.schedule(Time.now + 0.3, work)
      set.earliest.should == work
    end

    it "should return the item in the set with the lowest run_at value" do
      set.schedule(Time.now + 0.2, double("Work"))
      set.schedule(Time.now + 0.1, work = double("Work"))
      set.schedule(Time.now + 0.3, double("Work"))
      set.earliest.should == work
    end

  end

  describe "pop" do

    it "should return nil when the timeout expires" do
      set.pop(0.1).should be_nil
    end

    it "should block for the timeout value if there is no work in the queue" do
      start_time = Time.now
      set.pop(0.1)
      Time.now.should > start_time + 0.1
    end

    it "should block until the earliest work in the set" do
      start_time = Time.now
      set.schedule(start_time + 1.5, "work")
      set.schedule(start_time + 0.1, "work")
      set.pop(10)
      Time.now.should > start_time + 0.1
      Time.now.should < start_time + 0.2
    end

    it "should return immediately if tehre is work scheduled in the past" do
      set.schedule(Time.now - 0.1, "work")
      set.pop(10).should == "work"
    end

    it "should have removed the returned work from the set" do
      set.schedule(Time.now - 0.1, "work")
      set.pop(10)
      set.size.should == 0
    end

    it "should return old work in temporal order" do
      set.schedule(Time.now - 0.1, "work2")
      set.schedule(Time.now - 0.2, "work1")
      set.pop(10).should == "work1"
      set.pop(10).should == "work2"
    end

    it "should return the earliest work" do
      start_time = Time.now
      set.schedule(start_time + 0.1, "work")
      set.pop(10).should == "work"
    end

    it "should block until the earliest work, even if earlier work is added after the block" do
      start_time = Time.now
      Thread.new do
        sleep 0.1
        set.schedule(start_time + 0.2, "early")
      end
      set.schedule(start_time + 1.5, "late")
      set.pop(10)
      Time.now.should > start_time + 0.2
      Time.now.should < start_time + 0.3
    end

    it "should raise an exception if two threads try to block on the same work set" do
      Thread.new do
        set.pop(1)
      end
      sleep 0.1
      lambda {
        set.pop(1)
      }.should raise_exception(/another thread is already blocked/)
    end

    it "should not get deferred items caught outside the cache" do
      start_time = Time.now
      50.times { |i| set.schedule(start_time+0.1+i*0.001, "bulk") }
      set.schedule(start_time+0.2, "missing")

      50.times { set.pop(1).should == "bulk" }

      set.schedule(start_time+0.3, "final")
      set.pop(1).should == "missing"
      set.pop(1).should == "final"
    end

    it "should not delete all elements with the same run_at" do
      the_time = Time.now + 0.1
      set.schedule(the_time, "work-1")
      set.schedule(the_time, "work-2")
      2.times.collect { set.pop(1) }.sort.should == ["work-1", "work-2"]
    end
  end
end
