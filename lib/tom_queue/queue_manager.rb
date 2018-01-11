require 'bunny'
module TomQueue

  # Public: This is your interface to pushing work onto and
  #   pulling work off the work queue. Instantiate one of these
  #   and, if you're planning on operating as a consumer, then call
  #   become_consumer!
  #
  class QueueManager

    class QueuePriority

      attr_reader :name, :queue
      def initialize(name)
        @name = name
      end

      def setup(prefix, exchange, channel)
        @channel = channel
        @queue = channel.queue("#{prefix}.balance.#{@name}", :durable => true)
        @queue.bind(exchange, :routing_key => @name)
      end
      def peek
        # Perform a basic get. Calling Queue#get gets into a mess wrt the subscribe
        # below. Don't do it.
        response = @channel.basic_get(@queue.name, :manual_ack => true)
        response unless response.compact.empty?
      end
      def wait(&block)
        @queue.subscribe(:manual_ack => true, &block)
      end
      def to_s
        "<Priorty Queue routing_key='#{@name}'>"
      end
    end

    include LoggingHelper

    # Public: Return the string used as a prefix for all queues and exchanges
    attr_reader :prefix

    # Public: Returns the instance of Bunny that this object uses
    attr_reader :bunny

    # Internal: The work queues used by consumers
    #
    # Internal, this is an implementation detail. Accessor is mainly for
    # convenient testing
    #
    # Returns an array of the QueuePriority instances in priority order
    attr_reader :priorities

    # Internal: Return the queue object for a given priority level
    def queue(priority)
      priorities.find { |p| p.name == priority }.queue
    end

    # Internal: The exchange to which work is published
    #
    # Internal, this is an implementation detail. Accessor is mainly for
    # convenient testing
    #
    # Returns Bunny::Exchange instance.
    attr_reader :exchange

    class PersistentWorkPool < ::Bunny::ConsumerWorkPool
      def kill
      end
    end

    attr_reader :channel

    # Public: Create the manager.
    #
    # name  - used as a prefix for AMQP exchanges and queues.
    #         (this will default to TomQueue.default_prefix if set)
    #
    # NOTE: All consumers and producers sharing work must have the same
    #       prefix value.
    #
    # Returns an instance, duh!
    def initialize(prefix = nil, ident=nil)
      @ident = ident
      @bunny = TomQueue.bunny
      @prefix = prefix || TomQueue.default_prefix || raise(ArgumentError, 'prefix is required')

      # We create our on work pool so we don't continually create and
      # destroy threads. This pool ignores the kill commands issued by
      # the channels, so stays running, and is shared by all channels.
      @work_pool = PersistentWorkPool.new(4)

      # These are used when we block waiting for new messages, we declare here
      # so we're not constantly blowing them away and re-creating.
      @mutex = Mutex.new
      @condvar = ConditionVariable.new

      # Call the initial setup_amqp! to create the channels, exchanges and queues
      setup_amqp!
    end

    # Internal: Opens channels and declares the necessary queues, exchanges and bindings
    #
    # As a convenience to tests, this will tear-down any existing connections, so it is
    # possible to simulate a failed connection by calling this a second time.
    #
    # Retunrs nil
    def setup_amqp!
      debug "[setup_amqp!] (re) openining channels"
      # Test convenience
      @publisher_channel && @publisher_channel.close
      @channel && @channel.close

      # Publishing is going to come in from the host app so create a dedicated channel and mutex
      @publisher_channel = Bunny::Channel.new(@bunny, nil, @work_pool)
      @publisher_channel.open
      @publisher_mutex = Mutex.new

      @channel = Bunny::Channel.new(@bunny, nil, @work_pool)
      @channel.open
      @channel.basic_qos(1, true)

      @priorities = TomQueue.priorities.map do |name|
        QueuePriority.new(name)
      end

      # @exchange is used for both publishing and subscription so it's declared on the @channel
      @exchange = @channel.topic("#{@prefix}.work", :durable => true, :auto_delete => false)
      # @deferred_exchange is used only for publishing so declare it on the @publisher_channel
      @deferred_exchange = @publisher_channel.fanout("#{@prefix}.work.deferred", :durable => true, :auto_delete => false)

      @priorities.each { |p| p.setup(@prefix, @exchange, @channel) }
      nil
    end

    # Public: Publish some work to the queue
    #
    # work    - a serialized string representing the work
    # options - a hash of options, with keys:
    #   :priority = (default: NORMAL_PRIORITY) a priority constant from above
    #   :run_at   = (default: immediate) defer execution of this work for a given time
    #
    # Raises an ArgumentError unless the work is a string
    # Returns nil
    def publish(work, opts={})
      priority = opts.fetch('priority', opts.fetch(:priority, NORMAL_PRIORITY))
      run_at = opts.fetch('run_at', opts.fetch(:run_at, Time.now))

      raise ArgumentError, 'work must be a string' unless work.is_a?(String)
      raise ArgumentError, 'unknown priority level' unless @priorities.find { |p| p.name == priority }
      raise ArgumentError, ':run_at must be a Time object if specified' unless run_at.nil? or run_at.is_a?(Time)

      @publisher_mutex.synchronize do
        if run_at > Time.now
          publish_deferred work, run_at, priority
        else
          publish_immediate work, run_at, priority
        end
      end
      nil
    end

    def publish_immediate(work, run_at, priority)
      debug "[publish] Pushing work onto exchange '#{@exchange.name}' with routing key '#{priority}'"
      @exchange.publish(work, {
          :routing_key => priority,
          :headers => {
            :job_priority => priority,
            :run_at       => run_at.iso8601(4)
          }
        })
    end

    def publish_deferred(work, run_at, priority)
      debug "[publish] Handing work to deferred work manager to be run in #{run_at - Time.now}"

      @deferred_exchange.publish(work, mandatory: true, headers: {priority: priority, run_at: run_at.to_f})
    end

    # Public: Acknowledge some work
    #
    # work - the TomQueue::Work object to acknowledge
    #
    # Returns the work object passed.
    def ack(work)
      @channel.ack(work.response.delivery_tag)
      work
    end

    # Public: Reject some work
    #
    # work - the TomQueue::Work object to acknowledge
    # requeue - boolean, whether to requeue the work or drop it
    #
    # Returns the work object passed.
    def nack(work, requeue = true)
      @channel.nack(work.response.delivery_tag, false, requeue)
      work
    end

    # Public: Pop some work off the queue
    #
    # This call will block, if necessary, until work becomes available.
    #
    # Returns QueueManager::Work instance
    def pop(opts={})
      work = sync_poll_queues
      work ||= wait_for_message
      work
    end

    # Internal: Synchronously poll priority queues in order
    #
    # Returns: highest priority TomQueue::Work instance; or
    #          nil if no work is queued.
    def sync_poll_queues
      debug "[pop] Synchronously popping message"

      # Synchronously poll the head of all the queues in priority order
      response = nil
      @priorities.select { |priority| TomQueue.queue_consumer_filter.call(priority) }.find do |queue|
        debug "[pop] Polling queue '#{queue}'..."
        response = queue.peek
      end

      response && Work.new(self, *response)
    end

    # Internal: Setup a consumer and block, waiting for the first message to arrive
    # on any of the priority queues.
    #
    # Returns: TomQueue::Work instance
    def wait_for_message

      debug "[wait_for_message] setting up consumer, waiting for next message"

      consumer_thread_value = nil

      # Setup a subscription to all the queues. The channel pre-fetch
      # will ensure we get exactly one message delivered
      consumers = @priorities.select { |priority| TomQueue.queue_consumer_filter.call(priority) }.map do |queue|
        queue.wait do |*args|
          @mutex.synchronize do
            consumer_thread_value = args
            @condvar.signal
          end
        end
      end

      # Back on the calling thread, block on the callback above and, when
      # it's signalled, pull the arguments over to this thread inside the mutex
      response, header, payload = @mutex.synchronize do
        @condvar.wait(@mutex, 10.0) until consumer_thread_value
        consumer_thread_value
      end

      debug "[wait_for_message] Shutting down consumers"

      # Now, cancel the consumers - the prefetch level on the channel will
      # ensure we only got the message we're about to return.
      consumers.each { |c| c.cancel }

      # Return the message we got passed.
      TomQueue::Work.new(self, response, header, payload)
    end
  end
end
