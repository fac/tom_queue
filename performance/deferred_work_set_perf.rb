require 'perf_helper'

class Array
  def sum
    inject(0) { |a,v| a+=v }
  end
  def average
    sum / count
  end

  def report
    "Average: %.04fms      (max=%.04fms min=%.04fms)" % [average * 1000.0, max * 1000.0, min * 1000.0]
  end
end

def prep_queue(queue_size)
  set = TomQueue::DeferredWorkSet.new

  start_time = Time.now
  queue_size.times { set.schedule(start_time + rand * 30.0, "work") }
  set
end

def job_scheduling(queue_size)
  set = prep_queue(queue_size)

  100.times.collect do
    Benchmark.realtime do
      set.schedule(Time.now + rand * 30.0 - 15, "some_work")
    end
  end
end

def pop_earliest(queue_size)
  set = prep_queue(queue_size)

  100.times.collect do
    Benchmark.realtime do
      set.earliest
    end
  end
end


puts ""
puts "Job Scheduling:"
[50_000, 100_000, 500_000].each do |size|
  times = job_scheduling(size)
  puts " with %8i queue: %s" % [size, times.report]
end

puts ""
puts "Pop earliest:"
[50_000, 100_000, 500_000].each do |size|
  times = pop_earliest(size)
  puts " with %8i queue: %s" % [size, times.report]
end
