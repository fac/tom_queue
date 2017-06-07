module TomQueue
  class << self
    attr_accessor :test_logger
  end
end

RSpec.configure do |config|
  config.around(:each, worker: true) do |example|
    begin
      worker_read_pipe, worker_write_pipe = IO.pipe
      worker_pid = fork do
        TomQueue::DelayedJob::Job.reset!
        TomQueue.bunny = Bunny.new(AMQP_CONFIG)
        TomQueue.bunny.start
        TomQueue.test_logger = Logger.new(worker_write_pipe)
        Delayed::Worker.new.start
      end

      deferred_work_pid = fork do
        TomQueue::DelayedJob::Job.reset!
        TomQueue.bunny = Bunny.new(AMQP_CONFIG)
        TomQueue.bunny.start
        TomQueue::DeferredWorkManager.new(TomQueue.default_prefix).start
      end

      # We're in the parent process
      TomQueue.test_logger = worker_read_pipe
      example.run

    ensure
      TomQueue.test_logger.close
      Process.kill(:KILL, worker_pid)
      Process.kill(:KILL, deferred_work_pid)
    end
  end
end
