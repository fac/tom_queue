require 'bunny'
module TomQueue


  # Public: Priority values for QueueManager#publish
  #
  # Rather than an arbitrary numeric scale, we use distinct
  # priority values, one should be selected depending on the
  # type and use-case of the work.
  #
  # The scheduler simply trumps lower-priority jobs with higher
  # priority jobs. So ensure you don't saturate the worker with many
  # or lengthy high priority jobs as you'll negatively impact normal 
  # and bulk jobs.
  #
  # HIGH_PRIORITY - use where the job is relatively short and the
  #    user is waiting on completion. For example sending a password
  #    reset email.
  #
  # NORMAL_PRIORITY - use for longer-interactive tasks (rebuilding ledgers?)
  #
  # BULK_PRIORITY - typically when you want to schedule lots of work to be done
  #   at some point in the future - background emailing, cron-triggered 
  #   syncs, etc.
  #
  HIGH_PRIORITY = "high"
  NORMAL_PRIORITY = "normal"
  LOW_PRIORITY = "low"
  BULK_PRIORITY = "bulk"

  # Internal: A list of all the known priority values
  #
  # This array is where the priority ordering comes from, so get the
  # order right!
  PRIORITIES = [HIGH_PRIORITY, NORMAL_PRIORITY, LOW_PRIORITY, BULK_PRIORITY].freeze

  # Public: This is your interface to pushing work onto and
  #   pulling work off the work queue. Instantiate one of these
  #   and, if you're planning on operating as a consumer, then call
  #   become_consumer!
  #
  class QueueManager

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
    # Returns a hash of { "priority" => <Bunny::Queue>, ... }
    attr_reader :queues

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

      # Publishing is going to come in from the host app, as well as 
      # the Deferred thread, so create a dedicated channel and mutex
      @publisher_channel = Bunny::Channel.new(@bunny, nil, @work_pool)
      @publisher_channel.open
      @publisher_mutex = Mutex.new

      @channel = Bunny::Channel.new(@bunny, nil, @work_pool)
      @channel.open
      @channel.prefetch(1)

      @queues = {}

      @exchange = @channel.direct("#{@prefix}.work", :durable => true, :auto_delete => false)

      PRIORITIES.each do |priority|
        @queues[priority] = @channel.queue("#{@prefix}.balance.#{priority}", :durable => true)
        @queues[priority].bind(@exchange, :routing_key => priority)
      end

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
      raise ArgumentError, 'unknown priority level' unless PRIORITIES.include?(priority)
      raise ArgumentError, ':run_at must be a Time object if specified' unless run_at.nil? or run_at.is_a?(Time)

      if run_at > Time.now

        debug "[publish] Handing work to deferred work manager to be run in #{run_at - Time.now}"

        #  Make sure we explicitly pass all options in, even if they're the defaulted values
        DeferredWorkManager.instance(self.prefix).handle_deferred(work, {
          :priority => priority,
          :run_at   => run_at
        })
      else
        
        debug "[publish] Pushing work onto exchange '#{@exchange.name}' with routing key '#{priority}'"
        @publisher_mutex.synchronize do
          @publisher_channel.direct(@exchange.name, :passive=>true).publish(work, {
            :routing_key => priority,
            :headers => {
              :job_priority => priority,
              :run_at       => run_at.iso8601(4)
            }
          })
        end
      end
      nil
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

    # Public: Pop some work off the queue
    #
    # This call will block, if necessary, until work becomes available.
    #
    # Returns QueueManager::Work instance
    def pop(opts={})
      DeferredWorkManager.instance(self.prefix).ensure_running

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

      response, headers, payload = nil

      # Synchronously poll the head of all the queues in priority order
      PRIORITIES.find do |priority|
        debug "[pop] Popping '#{@queues[priority].name}'..."
        # Perform a basic get. Calling Queue#get gets into a mess wrt the subscribe
        # below. Don't do it.
        response, headers, payload = @channel.basic_get(@queues[priority].name, :ack => true)

        # Array#find will break out of the loop if we return a non-nil value.
        payload
      end

      payload && Work.new(self, response, headers, payload)
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
      consumers = PRIORITIES.map do |priority|
        @queues[priority].subscribe(:ack => true) do |*args|
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