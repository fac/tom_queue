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

      @exchange = @channel.fanout("#{prefix}-work", :durable => true, :auto_delete => false)
      @queue = @channel.queue("#{@prefix}-balance", :durable => true).bind(@exchange)
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


    # Public: Pop some work off the queue
    # 
    # opts - a hash of options, wiht keys:
    #   :block - (default: true) should the caller be blocked until work
    #            arrives, or return immediately with nil
    #
    # Returns QueueManager::Work instance
    #      or nil if there is no work and :block => true
    def pop(opts={})
      # work = @mutex.synchronize { 
      #   @condvar.wait(@mutex) if opts.fetch(:block, true) && @temp_queue.empty?
      #   @temp_queue.pop
      # }

      response, header, payload = p @queue.pop

      payload && TomQueue::Work.new(response, header, payload)
    end
    
  end

end