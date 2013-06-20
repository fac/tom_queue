module TomQueue

  # Public: This is your interface to pushing work onto and
  #   pulling work off the work queue. Instantiate one of these
  #   and, if you're planning on operating as a consumer, then call
  #   become_consumer!
  #
  class QueueManager

    # Public: Return the string used as a prefix for all queues and exchanges
    attr_reader :prefix

    # Public: Returns the instance of Bunny that this object uses
    attr_reader :bunny

    # Public: The work queue used by consumers
    # Returns a  Bunny::Queue object
    attr_reader :queue

    # Public: The exchange to which work is published
    # Returns a Bunny::Exchange
    attr_reader :exchange

    # Public: Create the manager.
    #
    # name  - used as a prefix for AMQP exchanges and queues.
    #
    # NOTE: All consumers and producers sharing work must have the same 
    #       prefix value.
    #
    # Returns an instance, duh!
    def initialize(prefix)
      @bunny = TomQueue.bunny
      @prefix = prefix
  
      @channel = @bunny.create_channel
      @channel.prefetch(1)

      @exchange = @channel.fanout("#{prefix}-work", :durable => true, :auto_delete => false)
      @queue = @channel.queue("#{@prefix}-balance", :durable => true).bind(@exchange)
      @setup_consumer = false
    end

    # Public: Purges all messages from queues. Dangerous!
    #
    # Please don't routinely use this, it's more a convenience 
    # function for tests to provide a blank slate
    #
    def purge!
      @queue.purge
    end


    # Public: Publish some work to the queue
    #
    # work - a serialized string representing the work
    #
    # Raises an ArgumentError unless the work is a string
    # Returns nil
    def publish(work)
      raise ArgumentError, 'work must be a string' unless work.is_a?(String)
      @exchange.publish(work)
      nil
    end

    # Internal: Configures the AMQP channel as a work consumer
    #
    # We pre-fetch jobs from the queue when we're a consumer, so this requires some
    # leg-work to set-up. We do this automatically, on the first call to pop.
    #
    def become_consumer!
      @mutex = Mutex.new
      @condvar = ConditionVariable.new
      @queue.subscribe(:ack => true, &method(:amqp_notification))
    end

    # Internal: Called on a Bunny work-thread when a message has been sent
    # from the broker
    #
    # delivery_info - the AMQP message operation object
    # headers       - the AMQP message headers
    # payload       - the AMQP message payload
    def amqp_notification(delivery_info, headers, payload)
      @mutex.synchronize do
        @next_message = [delivery_info, headers, payload]
        @condvar.signal
      end
    rescue
      puts $!.inspect
      exit(1)
    end

    # Internal: Acknowledge some work
    #
    # work - the TomQueue::Work object to acknowledge
    # 
    # Returns the work object passed.
    def ack(work)
      @channel.acknowledge(work.response.delivery_tag)
      work
    end

    # Public: Pop some work off the queue
    #
    # This call will block, if necessary, until work becomes available.
    #
    # Returns QueueManager::Work instance
    def pop(opts={})
      unless @setup_consumer
        @setup_consumer = true
        become_consumer!
      end

      # Get the next message, or stall until we get a signal of it's arrival
      response, header, payload, _ = @mutex.synchronize do

        # This will block waiting on a signal above (#amqp_notification) unless
        # @next_message has already been set!
        unless @next_message
          @condvar.wait(@mutex) 
        end

        # aah, ruby. In one swoop, this returns the @next_message array and
        # then sets @next_message to nil.
        _,_,_,@next_message = @next_message
      end



      payload && TomQueue::Work.new(self, response, header, payload)      
    end

  end

end