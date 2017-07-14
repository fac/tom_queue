module TomQueue
  class << self
    # Add a singleton location for the pipe for inter-process feedback
    attr_accessor :test_logger
  end
end

class TomQueue::DelayedJob::Job
  # Allow @@tomqueue_manager to be unmemoized between specs
  def self.reset!
    @@tomqueue_manager = nil
  end
end

RSpec.configure do |config|
  config.around(:each, worker: true) do |example|
    with_worker do
      example.run
    end
  end
end

def with_worker(&block)
  with_workers(1) do
    yield
  end
end

def with_workers(count, &block)
  worker_read_pipe, worker_write_pipe = IO.pipe

  child_pids = count.times.map do
    fork do
      TomQueue.bunny = Bunny.new(AMQP_CONFIG)
      TomQueue.bunny.start
      TomQueue.test_logger = Logger.new(worker_write_pipe)

      if native_worker?
        TomQueue::Worker.new.start
      else
        TomQueue::DelayedJob::Job.reset!
        Delayed::Worker.new.start
      end
    end
  end

  child_pids << fork do
    TomQueue::DelayedJob::Job.reset!
    TomQueue.bunny = Bunny.new(AMQP_CONFIG)
    TomQueue.bunny.start
    TomQueue::DeferredWorkManager.new(TomQueue.default_prefix).start
  end

  # We're in the parent process
  TomQueue.test_logger = worker_read_pipe

  yield

ensure
  TomQueue.test_logger.close
  child_pids.each { |pid| Process.kill(:KILL, pid) }
end
