require "tom_queue/stack"

module TomQueue
  class Worker
    class Invoke < TomQueue::Stack::Layer
      include LoggingHelper

      def call(options)
        job = options[:job]
        if job.is_a?(TomQueue::Persistence::Model)
          debug "[#{self.class.name}] Calling invoke_job on #{job.id}"
          job.invoke_job
          true
        else # external consumer work unit
          raise "Waaah"
        end
      end
    end
  end
end
