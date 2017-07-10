require "tom_queue/stack"

module TomQueue
  class Worker
    class Invoke < TomQueue::Stack::Layer
      include LoggingHelper

      # Public: Perform the work!
      #
      # options: Hash of details about the work to be performed
      #   :work: - a TomQueue::Work instance
      #   :job: - a TomQueue::Persistence::Model instance (optional)
      #
      # Returns true if the work succeeds or raises an error
      def call(options)
        work = options[:work]
        job = options[:job]
        if handler = self.class.external_handler(work)
          debug "Resolved external handler #{handler} for message. Calling the init block."
          block = handler.claim_work?(work)
          result = block.call(work)
          if result.is_a?(Delayed::Job) || result.is_a?(TomQueue::Persistence::Model)
            debug { "Got a job #{result.id}"}
            job = result
          else
            debug { "Handler returned non-job, I presume that is it."}
            return true
          end
        elsif job.is_a?(TomQueue::Persistence::Model)
          # All good
        else
          raise PermanentError.new("No handler available for #{options[:work].payload}", options)
        end

        debug "[#{self.class.name}] Calling invoke_job on #{job.id}"
        job.invoke_job
        true
      end

      private

      # Private: Find an external handler for the given work.
      #
      # Returns an ExternalConsumer class or nil
      def self.external_handler(work)
        TomQueue.handlers.find { |klass| klass.claim_work?(work) }
      end
    end
  end
end
