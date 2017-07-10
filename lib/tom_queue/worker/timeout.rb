require "tom_queue/stack"

module TomQueue
  class Worker
    class Timeout < TomQueue::Stack::Layer
      # Public: Apply a timeout to the work
      #
      # options: A hash describing the work
      #   :job: - a TomQueue::Persistence::Model instance (optional
      #
      # Returns the result of the chained call
      def call(options)
        runtime = self.class.max_run_time(options).to_i
        ::Timeout.timeout(runtime, TomQueue::WorkerTimeout) do
          chain.call(options)
        end
      end

      # Public: Determine the max runtime of the given options
      #
      # options: A hash describing the work
      #   :job: - a TomQueue::Persistence::Model instance (optional)
      #
      # Returns a value for Timeout
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
