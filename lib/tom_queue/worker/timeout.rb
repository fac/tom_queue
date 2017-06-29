require "tom_queue/stack"

module TomQueue
  class Worker
    class Timeout < TomQueue::Stack::Layer
      def call(options)
        runtime = self.class.max_run_time(options).to_i
        ::Timeout.timeout(runtime, TomQueue::WorkerTimeout) do
          chain.call(options)
        end
      end

      def self.max_run_time(options)
        if job = options[:job]
          job.max_run_time || TomQueue::Worker.max_run_time
        else
          TomQueue::Worker.max_run_time
        end
      end
    end
  end
end
