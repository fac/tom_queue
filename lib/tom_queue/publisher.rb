module TomQueue
  class Publisher
    def publish(bunny, exchange_type:, exchange_name:, exchange_options:, message_payload:, message_options:)
      exchange = bunny.create_channel.exchange(exchange_name, exchange_options.merge(type: exchange_type))
      exchange.publish(message_payload, message_options)
    end
  end
end
