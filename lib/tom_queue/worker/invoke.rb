require "tom_queue/stack"

module TomQueue
  class Worker
    class Invoke < TomQueue::Stack::Layer
      def call(options)
        if job = options[:job] && job.is_a?(TomQueue::Persistence::Model)
          job.invoke_job
        else # external consumer work unit
          raise "Waaah"
        end
      end
    end
  end
end
