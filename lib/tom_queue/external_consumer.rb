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
  #     bind_exchange(:fanout, 'exchange_name') do |work|
  #       .. do something with a work (a TomQueue::Work object) ..
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
  # Block behaviour
  # ---------------
  #
  # You should do the minimum work necessary in the bind_exchange block ideally just
  # creating a delayed job object to do the actual work of reacting to the message.
  #
  # If you return a Delayed::Job record to the block caller, then the worker will immediately
  # perform that job. Also, if you omit the block entirely, there is a default block provided
  # that carries out the following:
  #
  #   class MyAwesomeConsumer
  #     bind_exchange(...) do |work|
  #       new(work.payload, work.headers).delay.perform
  #     end
  #
  #     def initialize(payload, headers)
  #       ...
  #     end
  #
  #     def perform
  #       ... do something! ...
  #     end
  #   end
  #
  # This returns a Delayed::Job instance (as per the behaviour of the .delay method) which is then
  # immediately called. If your block looks like the above, then you can omit it entirely!
  #
  module ExternalConsumer

    # This class is the producer that is
    class Producer
      def initialize(type, name, config={}, *args)
        @type, @name =  type, name
        @routing_key = config.fetch(:routing_key, nil)
        @auto_delete = config.fetch(:auto_delete, false)
        @durable = config.fetch(:durable, true)
        @encoder = config.fetch(:encoder, nil)
      end

      # Public: Push a message to the AMQP exchange associated with this consumer
      def publish(message, options = {})
        message = @encoder.encode(message) if @encoder
        routing_key = options.fetch(:routing_key, @routing_key)

        exchange.publish(message, :routing_key => routing_key)
      end

      private

      # Internal: set up an exchange for publishing messages to
      def exchange
        Delayed::Job.tomqueue_manager.channel.exchange(@name,
          :type => @type,
          :auto_delete => @auto_delete,
          :durable => @durable
        )
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
        encoder = opts.fetch(:encoder, nil)
        block ||= lambda do |work|
          payload = if encoder
            encoder.decode(work.payload)
          else
            work.payload
          end
          new(payload, work.headers).delay.perform
        end
        binding_defaults = { :routing_key => "#" }
        @bind_exchange = [type, name, binding_defaults.merge(opts), block]
        @producer_args = [type, name, opts, block]
      end

      # Public: Create and return a producer for the consumer
      #
      # Returns TomQueue::ExternalConsumer::Producer object
      def producer
        TomQueue::ExternalConsumer::Producer.new(*@producer_args)
      end

      def claim_work?(work)
        type, name, opts, block = @bind_exchange

        (work.response.exchange == @bind_exchange[1]) ? @bind_exchange.last : false
      end

      def setup_binding(manager)
        type, name, opts, block = @bind_exchange
        encoder = opts.fetch(:encoder, nil)
        priority = opts.fetch(:priority, TomQueue::NORMAL_PRIORITY)
        routing_key = opts.fetch(:routing_key, nil)
        auto_delete = opts.fetch(:auto_delete, false)
        durable = opts.fetch(:durable, true)

        # make sure the exchange is declared
        manager.channel.exchange(name, :type => type, :auto_delete => auto_delete, :durable => durable)
        manager.queues[priority].bind(name, :routing_key => routing_key)
      end
    end

  end
end


