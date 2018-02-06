require 'tom_queue/helper'

describe TomQueue::DeferredWorkSet do
  let(:set) { TomQueue::DeferredWorkSet.new }

  it "should be creatable" do
    expect(set).to be_a(TomQueue::DeferredWorkSet)
  end

  it "should allow work to be scheduled" do
    set.schedule(Time.now + 0.2, "something")
    set.schedule(Time.now + 0.3, "else")
    expect(set.size).to eq(2)
  end

  describe "earliest" do

    it "should return nil if there is no work in the set" do
      expect(set.earliest).to be_nil
    end

    it "should return the only item if there is one item in the set" do
      work = double("Work")
      set.schedule( Time.now + 0.3, work)
      expect(set.earliest).to eq(work)
    end

    it "should return the item in the set with the lowest run_at value" do
      set.schedule( Time.now + 0.2, work1 = double("Work") )
      set.schedule( Time.now + 0.1, work2 = double("Work") )
      set.schedule( Time.now + 0.3, work3 = double("Work") )
      expect(set.earliest).to eq(work2)
    end

  end

  describe "pop" do

    it "should return nil when the timeout expires" do
      expect(set.pop(0.1)).to be_nil
    end

    it "should block for the timeout value if there is no work in the queue" do
      start_time = Time.now
      set.pop(0.1)
      expect(Time.now).to be > (start_time + 0.1)
    end

    it "should block until the earliest work in the set" do
      start_time = Time.now
      set.schedule(start_time + 1.5, "work")
      set.schedule(start_time + 0.1, "work")
      set.pop(10)
      expect(Time.now).to be > (start_time + 0.1)
      expect(Time.now).to be < (start_time + 0.2)
    end

    it "should return immediately if tehre is work scheduled in the past" do
      set.schedule(Time.now - 0.1, "work")
      expect(set.pop(10)).to eq("work")
    end

    it "should have removed the returned work from the set" do
      set.schedule(Time.now - 0.1, "work")
      set.pop(10)
      expect(set.size).to eq(0)
    end

    it "should return old work in temporal order" do
      set.schedule(Time.now - 0.1, "work2")
      set.schedule(Time.now - 0.2, "work1")
      expect(set.pop(10)).to eq("work1")
      expect(set.pop(10)).to eq("work2")
    end

    it "should return the earliest work" do
      start_time = Time.now
      set.schedule(start_time + 0.1, "work")
      expect(set.pop(10)).to eq("work")
    end

    it "should block until the earliest work, even if earlier work is added after the block" do
      start_time = Time.now
      Thread.new do
        sleep 0.1
        set.schedule(start_time + 0.2, "early")
      end
      set.schedule(start_time + 1.5, "late")
      set.pop(10)
      expect(Time.now).to be > (start_time + 0.2)
      expect(Time.now).to be < (start_time + 0.3)
    end

    it "should raise an exception if two threads try to block on the same work set" do
      Thread.new do
        set.pop(1)
      end
      sleep 0.1
      expect {
        set.pop(1)
      }.to raise_exception(/another thread is already blocked/)
    end

    it "should not get deferred items caught outside the cache" do
      start_time = Time.now
      50.times { |i| set.schedule(start_time+0.1+i*0.001, "bulk") }
      set.schedule(start_time+0.2, "missing")

      50.times { expect(set.pop(1)).to eq("bulk") }

      set.schedule(start_time+0.3, "final")
      expect(set.pop(1)).to eq("missing")
      expect(set.pop(1)).to eq("final")
    end

    it "should not delete all elements with the same run_at" do
      the_time = Time.now + 0.1
      set.schedule(the_time, "work-1")
      set.schedule(the_time, "work-2")
      expect(2.times.collect { set.pop(1) }.sort).to eq(["work-1", "work-2"])
    end
  end

end
