module TomQueue
  # Adapter for TomQueue using ActiveRabbit to publish messages
  #
  # Expects TomQueue & ActiveRabbit to have been loaded/setup before this file is required.
  # Assign to TomQueue:: QueueManager.publisher to handle publishing duties:
  #
  #   publisher = TomQueue::ActiveRabbitPublisher.new(handler: ActiveRabbit.default)
  #   TomQueue::QueueManager.publisher = publisher
  #
  class ActiveRabbitPublisher
    attr_accessor :handler

    # Public: sets up ActiveRabbitPublisher instance
    #
    # handler: [ActiveRabbit] pool to use for publishing. dup'd before keeping.
    #
    # Returns nothing
    def initialize(handler:)
      self.handler = handler.dup
    end

    # Public: creates topic exchange wrapper
    #
    # exchange_name [String] name of the exchange
    # exchange_arguments [Hash] any other arguments for Bunny::Exchange#initialize
    #
    # Returns ActiveRabbit::ExchangeWrapper (which responds to #publish)
    def topic(exchange_name, _options = {})
      handler.exchange(exchange_name)
    end
  end
end
