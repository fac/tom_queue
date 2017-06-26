require "tom_queue/delayed_job/errors"
require "tom_queue/enqueue/publish"

module TomQueue
  class Worker
    class Reschedule < TomQueue::Stack::Layer
      include LoggingHelper

      def call(work, options)
        # Pass thru and catch exceptions
        chain.call(work, options)

      rescue DelayedJob::RetryableError => ex
        warn ex.message
        self.class.republish(work)
        [true, options.merge(work: work)]

      rescue DelayedJob::PermanentError => ex
        warn ex.message
        [true, options.merge(work: work)]

      rescue => ex
        warn ex.message
        raise
      end

      private

      # Private: Republish a job onto the queue
      #
      # job - a TomQueue::Persistence::Model instance
      # options - a Hash of options
      #   :run_at: - the time to requeue the message for (optional)
      #
      # Returns nothing
      def self.republish(job, options)
        @@republisher ||= Publish.new
        @@republisher.call(job, options)
      end
    end
  end
end
