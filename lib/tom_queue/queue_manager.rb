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
  BULK_PRIORITY = "bulk"

  # Internal: A list of all the known priority values
  #
  # This array is where the priority ordering comes from, so get the
  # order right!
  PRIORITIES = [HIGH_PRIORITY, NORMAL_PRIORITY, BULK_PRIORITY].freeze

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

    # Internal: The DeferredManager object created to handle deferred work
    #
    # Internal, this accessor is to make for convenient testing.#
    #
    # Returns TomQueue::DeferredWorkManager
    attr_reader :deferred_manager

    # Internal: The work queues used by consumers
    #
    # Internal, this is an implementation detail. Accessor is mainly for 
    # convenient testing
    # 
    # Returns a hash of { "priority" => <Bunny::Queue>, ... }
    attr_reader :queues

    # Internal: The exchanges to which work is published, keyed by the priority
    #
    # Internal, this is an implementation detail. Accessor is mainly for 
    # convenient testing
    #
    # Returns a hash of { "priority" => <Bunny::Exchange>, ... }
    attr_reader :exchanges

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
  
      @deferred_manager = DeferredWorkManager.new(@prefix, self)

      @channel = @bunny.create_channel
      @channel.prefetch(1)

      @exchanges = {}
      @queues = {}

      # These are used when we block waiting for new messages, we declare here
      # so we're not constantly blowing them away and re-creating.
      @mutex = Mutex.new
      @condvar = ConditionVariable.new

      PRIORITIES.each do |priority|
        @exchanges[priority] = @channel.fanout("#{@prefix}.work.#{priority}", :durable => true, :auto_delete => false)
        @queues[priority] = @channel.queue("#{@prefix}.balance.#{priority}", :durable => true)
        @queues[priority].bind(@exchanges[priority])
      end
    end

    # Public: Purges all messages from queues. Dangerous!
    #
    # Please don't routinely use this, it's more a convenience 
    # function for tests to provide a blank slate
    #
    def purge!
      @queues.values.each { |q| q.purge }
      deferred_manager.purge!
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
      priority = opts.fetch(:priority, NORMAL_PRIORITY)
      run_at = opts.fetch(:run_at, Time.now)

      raise ArgumentError, 'work must be a string' unless work.is_a?(String)
      raise ArgumentError, 'unknown priority level' unless PRIORITIES.include?(priority)
      raise ArgumentError, ':run_at must be a Time object if specified' unless run_at.nil? or run_at.is_a?(Time)

      if run_at > Time.now
        # Make sure we explicitly pass all options in, even if they're the defaulted values
        deferred_manager.handle_deferred(work, {
          :priority => priority,
          :run_at   => run_at
        })
      else
        @exchanges[priority].publish(work, {
          :headers => {
            :job_priority => priority,
            :run_at       => run_at.iso8601(4)
          }
        })
      end
      nil
    end

    # Public: Acknowledge some work
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

      # Synchronously poll the head of all the queues
      PRIORITIES.find do |priority|

        # Perform a basic get. Calling Queue#get gets into a mess wrt the subscribe
        # below. Don't do it.
        @next_message = @channel.basic_get(@queues[priority].name, :ack => true)
        
        # Find will break out of the loop if we return a non-nil value.
        @next_message.first
      end

      response, header, payload = if @next_message.first

        # The poll returned a waiting message, lets use that!
        @next_message

      else

        # The poll returned nothing - setup a subscription to all the queues
        # the channel pre-fetch will ensure we get exactly one message delivered
        consumers = PRIORITIES.map do |priority|
          @queues[priority].subscribe(:ack => true) do |a, b, c|
            @mutex.synchronize do
              @next_message = [a,b,c]
              @condvar.signal
            end
          end
        end

        # We /probably/ didn't get @next_message set already, but just in-case
        # this thread stalled, we use a @mutex and only block on the condvar if
        # @next-message is nil, as we expect.
        @mutex.synchronize do
          @condvar.wait(@mutex) unless !@next_message
        end

        # We have a message - cancel the consumers.
        # The prefetch ensures that we won't have been delivered any extra
        # messages in the interviening time.
        consumers.each { |c| c.cancel }
      
        # Return the message we got passed.
        @next_message
      end

      @next_message = nil
      payload && TomQueue::Work.new(self, response, header, payload)      
    end
  end
end