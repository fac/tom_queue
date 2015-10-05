require "stomp"

module TomQueue
  # Public: publishes RMQ messages via Stomp
  #
  # Plug into TomQueue with the following:
  #
  #     TomQueue::QueueManager.publisher = TomQueue::StompPublisher.new(config)
  #
  # IMPORTANT: This publisher **cannot** create the exchanges or queue bindings,
  # these MUST be created elsewhere before we can publish messages and have them
  # routed.
  #
  class StompPublisher

    # Internal: wraps an "exchange" as a return object from StompPublisher#topic
    #
    # Lets us hold relevant details for the exchange we want to publish to, and
    # also defines #publish as required by TomQueue::QueueManager.publisher
    #
    class ExchangeWrapper
      attr_reader :exchange_name

      def initialize(stomp_publisher, exchange_name)
        @stomp_publisher = stomp_publisher
        @exchange_name = exchange_name.freeze
      end

      # Public: publishes the message to the exchange
      #
      # message [String] body of RMQ message
      # options [Hash] 
      #
      # Returns Stomp::Client#publish return value
      def publish(message, key: nil, headers: {})
        stomp_publisher.client.publish(stomp_exchange(name: exchange_name, key: key), message, headers)
      end

      private

      attr_reader :stomp_publisher

      def stomp_exchange(name:, key: nil)
        "/exchange/#{name}".tap {|e| e << "/#{key}" if key }
      end
    end

    attr_reader :stomp_config

    def initialize(stomp_config:)
      @stomp_config = stomp_config
    end

    # Public: fakes creation of the topic exchange
    #
    # Returns ExchangeWrapper instance which responds to #publish
    def topic(exchange_name, _options = {})
      ExchangeWrapper.new(self, exchange_name)
    end

    def client
      @client ||= Stomp::Client.new(stomp_config)
    end

  end
end
