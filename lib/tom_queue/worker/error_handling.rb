require "tom_queue/errors"
require "tom_queue/enqueue/publish"

module TomQueue
  class Worker
    class ErrorHandling < TomQueue::Stack::Layer
      include LoggingHelper

      # Public: Pass thru layer for a work unit, to catch any exceptions when processing
      #
      # Returns nothing
      def call(*args)
        chain.call(*args)

      rescue TomQueue::RepublishableError => ex
        # This exception will have caused the message to be acked, but we need to republish it
        warn ex.message
        self.class.republish(ex)
        false

      rescue PermanentError, RetryableError => ex
        # This exception will have caused the message to be acked/nacked, and we don't need to republish it
        warn ex.message
        false

      rescue => ex
        # An unexpected exception occurred.
        error ex.message
        TomQueue.exception_reporter && TomQueue.exception_reporter.notify(ex)
        raise

      end

      private

      # Private: Republish a job onto the queue
      #
      # exception - a TomQueue::RepublishableError
      #
      # Returns nothing
      def self.republish(exception)
        @@republisher ||= TomQueue::Enqueue::Publish.new
        @@republisher.call(exception.job || exception.work, exception.options)
      end
    end
  end
end
