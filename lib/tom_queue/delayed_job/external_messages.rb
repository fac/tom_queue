require 'active_support/concern'

module TomQueue
  module DelayedJob

    # Internal: This is mixed into the Job class, in order to support the handling of
    #           externally sourced AMQP messages
    #
    module ExternalMessages
      extend ActiveSupport::Concern

      module ClassMethods

        # Internal: This resolves the correct handler for a given AMQP response
        #
        # work - the TomQueue::Work object
        #
        # Returns nil if no handler can be resolved
        def resolve_external_handler(work)

          # Look for a matching source exchange!
          klass = TomQueue::DelayedJob.handlers.find { |klass| klass.claim_work?(work) }
          if klass
            debug { "Resolved external handler #{klass} for message. Calling the init block." }

            block = klass.claim_work?(work)

            job = block.call(work)
            if job.is_a?(Delayed::Job) || job.is_a?(TomQueue::Persistence::Model)
              debug { "Got a job #{job.id}"}
              job
            else
              debug { "Handler returned non-job, I presume that is it."}
              true
            end
          else
            debug { "No external handler wants message, returning false" }
            false
          end
        end

        # Internal: This is called to setup the external handlers with a given queue-manager
        #
        # queue_manager - TomQueue::QueueManager to configure against
        #
        def setup_external_handler(queue_manager)
          TomQueue::DelayedJob.handlers.each do |klass|
            klass.setup_binding(queue_manager)
          end
        end

      end
    end
  end
end
