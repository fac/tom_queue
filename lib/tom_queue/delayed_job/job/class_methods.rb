require "tom_queue/job/preparer"
require "tom_queue/persistence/model"

module TomQueue
  module DelayedJob
    module ClassMethods
      # Public: Override Delayed::Job.enqueue
      # Allows us to skip DJ for enqueuing new work
      #
      def enqueue(*args)
        TomQueue.enqueue(*args)
      end
    end
  end
end
