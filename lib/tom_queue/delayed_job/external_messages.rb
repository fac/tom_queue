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
          handler = TomQueue::DelayedJob.handlers.find { |klass| klass.amqp_binding[:exchange] == work.response.exchange } 

          if handler
            handler.on_message(work.payload)
          else
            false
          end
        end

        # Internal: This is called to setup the external handlers with a given queue-manager
        #
        # queue_manager - TomQueue::QueueManager to configure against
        #
        def setup_external_handler(queue_manager)


          TomQueue::DelayedJob.handlers.each do |klass|
            binding_data = klass.amqp_binding
            priority = binding_data.fetch(:priority, TomQueue::NORMAL_PRIORITY)
            exchange = binding_data.fetch(:exchange)
            routing_key = binding_data.fetch(:routing_key, '#')

            puts "Woo, setup binding from #{exchange} (#{routing_key}) to queue for priority #{priority}."

            queue_manager.queues[priority].bind(exchange, :routing_key => routing_key)
          end

        end

      end
    end
  end
end
