require "tom_queue/stack"

module TomQueue
  class Worker
    class Pop < TomQueue::Stack::Layer
      include LoggingHelper
      include TomQueue::DelayedJob::ExternalMessages

      # Public: Pops a work unit from the queue manager and passes it into the chain
      #
      #
      #
      # Returns [work, options]
      def call(_, options)
        work = self.class.pop(options[:worker])

        return [false, options] unless work

        chain.call(work, options).tap do
          work.ack!
        end

      rescue SignalException => e
        work && work.nack!
        error "[#{self.class.name}] SignalException in worker stack, nacked work (will be requeued): #{e.message}."
        [false, options.merge(work: work)]

      rescue Exception => e
        work && work.nack!
        error "[#{self.class.name}] Exception in worker stack, nacked work (will be requeued): #{e.message}."
        TomQueue.exception_reporter && TomQueue.exception_reporter.notify(e)
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
      # Returns a TomQueue::Work instance
      def self.pop(worker, max_run_time = TomQueue::Worker.max_run_time)
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
