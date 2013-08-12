require 'active_support/concern'

module TomQueue

  # Public: This module can be mixed into a class to make that class
  #   a consumer of messages to an AMQP exchange. Mixing in this class
  #   provides the necessary methods, but you need to configure which
  #   exchange the messages get pulled from.
  #
  # Example:
  #
  #   class MyAwesomeConsumer
  #
  #     include TomQueue::ExternalConsumer
  #     bind_exchange(:fanout, 'exchange_name') do |message|
  #       .. do something with a message ..
  #     end
  #
  #   end
  #
  # Then you just need to register the consumer with TomQueue for it to receive
  # messages:
  #
  #    TomQueue.consumers << MyAwesomeConsumer
  #
  # In addition to receiving messages, this mixin also adds a producer accessor
  # which returns an object that can be used to publish a message to the appropriate
  # exchange. Example:
  #
  #    MyAwesomeConsumer.publisher.publish("my message here")
  #
  # which will pass the message to the consumer block
  #
  module ExternalConsumer

    # This class is the producer that is 
    class Producer
      def initialize(type, name, opts={}, *args)
        @type, @name, @opts = type, name, opts
      end

      # Public: Push a message to the AMQP exchange associated with this consumer
      def publish(message)
        Delayed::Job.tomqueue_manager.channel.exchange(@name, :type => @type).publish(message)
      end
    end

    extend ActiveSupport::Concern

    module ClassMethods
      # Public: Binds this consumer to an AMQP exchange.
      #
      # type - the type of exchange, from :direct, :fanout, :topic or :headers
      # name - the name of the exchange
      # opts - some options:
      #   :priority = a TomQueue priority constant  (defaults to TomQueue::NORMAL_PRIORITY)
      #   :durable  = should this exchange be durable (defaults to true)
      # &block - called when a message is received
      #
      def bind_exchange(type, name, opts={}, &block)
        @bind_exchange = [type, name, opts, block]
      end

      # Public: Create and return a producer for the consumer
      #
      # Returns TomQueue::ExternalConsumer::Producer object
      def producer
        TomQueue::ExternalConsumer::Producer.new(*@bind_exchange)
      end

      def claim_work?(work)
        p work.response.exchange
        p @bind_exchange[1]
        work.response.exchange == @bind_exchange[1]
      end

      def setup_binding(manager)
        type, name, opts, block = @bind_exchange

#        priority = binding_data.fetch(:priority, TomQueue::NORMAL_PRIORITY)
#        exchange = binding_data.fetch(:exchange)
#        routing_key = binding_data.fetch(:routing_key, '#')
        priority = TomQueue::NORMAL_PRIORITY

        # make sure the exchange is declared
        manager.channel.exchange(name, :type => type)
        manager.queues[priority].bind(name)

      end
    end

  end
end


