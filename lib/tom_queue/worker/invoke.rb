require "tom_queue/stack"

module TomQueue
  class Worker
    class Invoke < TomQueue::Stack::Layer
      def call(job_or_work, options)
        if job_or_work.is_a?(TomQueue::Persistence::Model)
          job.invoke_job
          [true, options]
        else
          raise "Waaah"
        end
      end
    end
  end
end
