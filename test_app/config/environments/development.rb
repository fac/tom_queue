TomQueue.default_prefix = "tomqueue-dev"

if defined?(AMQP_CONFIG) && !!AMQP_CONFIG && !!TomQueue.default_prefix
  Rails.logger.info("[TomQueue] Connecting to AMQP server...")
  begin
    TomQueue.bunny = Bunny.new(AMQP_CONFIG)
    TomQueue.bunny.start
    TomQueue::DelayedJob.apply_hook!
  rescue Bunny::Exception => e
    Rails.logger.error "Failed to connect to RabbitMQ server for TomQueue: #{e.message}: #{e.inspect}"
    Rails.logger.warn "DelayedJob has not been modified."
  end
end

