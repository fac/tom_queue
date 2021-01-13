require 'tom_queue/work'
module TomQueue

  # Internal: This is an internal class that oversees the delay of "deferred"
  # work, that is, work with a future :run_at value.
  #
  # DefferedWorkManager#new takes a prefix value to set up RabbitMQ exchange
  # and queue for deferred jobs
  #
  # Work is also pushed to this maanger by the QueueManager when it needs to be deferred.
  #
  # For the purpose of listening to the deferred jobs queue and handling jobs when they're
  # ready to run DeferredWorkManager::start is intended to run AS A SEPARATE PROCESS
  #
  # Internally, this class opens a separate AMQP channel (without a prefetch limit) and
  # leaves all the deferred messages in an un-acked state. An internal timer is maintained
  # to delay until the next message is ready to be sent, at which point the message is
  # dispatched back to the QueueManager, and at some point will be processed by a worker.
  #
  # If the host process of this manager dies for some reason, the broker will re-queue the
  # un-acked messages onto the deferred queue, to be re-popped by another worker in the pool.
  #
  class DeferredWorkManager

    include LoggingHelper

    attr_accessor :prefix, :exchange, :queue, :consumer, :deferred_set, :out_manager, :channel

    def initialize(prefix = nil)
      @prefix = prefix || TomQueue.default_prefix
      @prefix || raise(ArgumentError, 'prefix is required')
      setup_amqp
      @deferred_set = DeferredWorkSet.new
      @out_manager = QueueManager.new(prefix)
      @out_manager.start_consumers!
    end


    # Internal: Creates the bound exchange and queue for deferred work on the provided channel
    #
    # Returns [ <exchange object>, <queue object> ]
    def setup_amqp
      @channel = TomQueue.bunny.create_channel
      @channel.prefetch(0)

      @exchange = channel.fanout("#{prefix}.work.deferred",
          :durable     => true,
          :auto_delete => false)

      @queue = channel.queue("#{prefix}.work.deferred",
          :durable     => true,
          :auto_delete => false).bind(exchange.name)
    end

    # Internal: This is called on a bunny internal work thread when
    # a new message arrives on the deferred work queue.
    #
    # A given message will be delivered only to one deferred manager
    # so we simply schedule the message in our DeferredWorkSet (which
    # helpfully deals with all the cross-thread locking, etc.)
    #
    # response - the AMQP response object from Bunny
    # headers  - (Hash) a hash of headers associated with the message
    # payload  - (String) the message payload
    #
    #
    def schedule(response, headers, payload)
      run_at = Time.at(headers[:headers]['run_at'])

      # schedule it in the work set
      deferred_set.schedule(run_at, [response, headers, payload])
    rescue Exception => e
      r = TomQueue.exception_reporter
      r && r.notify(e)

      ### Avoid tight spinning workers by not re-queueing redlivered messages more than once!
      response.channel.reject(response.delivery_tag, !response.redelivered?)
    end

    def start(&started_callback)
      debug "[DeferredWorkManager] Deferred process starting up"

      # This block will get called-back for new messages
      @consumer = queue.subscribe(:manual_ack => true, &method(:schedule))

      started_callback.call if started_callback

      # This is the core event loop - we block on the deferred set to return messages
      # (which have been scheduled by the AMQP consumer). If a message is returned
      # then we re-publish the messages to our internal QueueManager and ack the deferred
      # message
      loop do
        # This will block until work is ready to be returned, interrupt
        # or the 10-second timeout value.
        response, headers, payload = deferred_set.pop(2)

        if response
          debug "[DeferredWorkManager] Popped a message with run_at: #{headers && headers[:headers]['run_at']}"
          headers[:headers].delete('run_at')
          out_manager.publish(payload, headers[:headers])
          channel.ack(response.delivery_tag)
        end
      end
    rescue SignalException
      consumer.cancel
      channel && channel.close
    rescue Exception => e
      error e
      reporter = TomQueue.exception_reporter
      reporter && reporter.notify($!)
    end
  end
end
