require "tom_queue/stack"

module TomQueue
  class Worker
    class Pop < TomQueue::Stack::Layer
      include LoggingHelper
      include TomQueue::DelayedJob::ExternalMessages

      # Public: Pops a work unit from the queue manager and passes it into the chain
      #
      # options - hash of options for this stack
      #   :worker: - a TomQueue::Worker instance
      #
      # Returns the result of the chained call
      def call(options = {})
        return unless work = self.class.pop(options[:worker])

        chain.call(options.merge(work: work)).tap do
          work.ack!
        end

      rescue RetryableError
        # nack the work so it's returned to the queue
        work && work.nack!
        raise

      rescue RepublishableError, PermanentError
        # ack the work, either it will be republished or dropped
        work && work.ack!
        raise

      rescue SignalException => ex
        work && work.nack!
        options[:worker].stop
        raise RetryableError, "SignalException in worker stack, nacked work (will be requeued): #{ex.message}."

      rescue => ex
        # TODO: nack the work, but only a limited number of times
        work && work.nack!
        raise
      end

      # Internal: The QueueManager instance
      #
      # Returns a memoized TomQueue::QueueManager
      def self.queue_manager
        @@tomqueue_manager ||= TomQueue::QueueManager.new.tap do |manager|
          setup_external_handler(manager)
        end
      end

      # Internal: Pop a job from the queue
      #
      # This function will block until a job becomes available to process. It tweaks
      # the `TomQueue::Worker.raise_signal_exceptions` during the blocking stage so
      # the process can be interrupted.
      #
      # Returns a TomQueue::Work instance or nil if no work is available
      def self.pop(worker)
        # Grab a job from the QueueManager - will block here, ensure we can be interrupted!
        TomQueue::Worker.raise_signal_exceptions, old_value = true, TomQueue::Worker.raise_signal_exceptions
        work = queue_manager.pop
        TomQueue::Worker.raise_signal_exceptions = old_value

        if work.nil?
          warn "[#{self.name}] TomQueue#pop returned nil, stalling for a second."
          sleep 1.0
        end

        work
      end
    end
  end
end
