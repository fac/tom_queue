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
  DEFAULT_PRIORITY = LOW_PRIORITY

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
    def initialize(prefix = nil)
      @prefix = prefix || TomQueue.default_prefix || raise(ArgumentError, 'prefix is required')

      # We create our on work pool so we don't continually create and
      # destroy threads. This pool ignores the kill commands issued by
      # the channels, so stays running, and is shared by all channels.
      @work_pool = PersistentWorkPool.new(4)

      # These are used when we block waiting for new messages, we declare here
      # so we're not constantly blowing them away and re-creating.
      @mutex = Mutex.new
      @condvar = ConditionVariable.new

      # Publishing is going to come in from the host app so create a dedicated channel and mutex
      @publisher_mutex = Mutex.new

      # Call the initial setup_amqp! to create the channels, exchanges and queues
      @consumers_started = false

      # Setting job_limit > 0 will cause the worker to exit after processing this number of jobs
      @job_limit = TomQueue.job_limit || 0
      @job_count = 0
    end

    # Internal: Opens channels and declares the necessary queues, exchanges and bindings
    #
    # As a convenience to tests, this will tear-down any existing connections, so it is
    # possible to simulate a failed connection by calling this a second time.
    #
    # Retunrs nil
    def start_consumers!
      return if consumers_started?

      debug "[setup_amqp!] (re) opening channels"

      # Test convenience
      @channel && @channel.close

      @channel = Bunny::Channel.new(TomQueue.bunny, nil, @work_pool)
      @channel.open
      @channel.basic_qos(1, true)

      @queues = {}

      @exchange = @channel.topic("#{@prefix}.work", :durable => true, :auto_delete => false)

      PRIORITIES.each do |priority|
        @queues[priority] = @channel.queue("#{@prefix}.balance.#{priority}", :durable => true)
        @queues[priority].bind(@exchange, :routing_key => priority)
      end

      @consumers_started = true
      nil
    end

    # Public: Have the consumers been started yet?
    def consumers_started?
      @consumers_started
    end

    def ensure_consumers_started!
      start_consumers! unless consumers_started?
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
      TomQueue.publisher.publish(
        TomQueue.bunny,
        exchange_type: :topic,
        exchange_name: "#{@prefix}.work",
        exchange_options: { durable:true, auto_delete:false },
        message_payload: work,
        message_options: {
          routing_key: priority,
          headers: { priority: priority, run_at: run_at.iso8601(4) }
        }
      )
    end

    def publish_deferred(work, run_at, priority)
      debug "[publish] Handing work to deferred work manager to be run in #{run_at - Time.now}"

      TomQueue.publisher.publish(
        TomQueue.bunny,
        exchange_type: :fanout,
        exchange_name: "#{@prefix}.work.deferred",
        exchange_options: { durable:true, auto_delete:false },
        message_payload: work,
        message_options: {
          mandatory: true,
          headers: { priority: priority, run_at: run_at.to_f }
        }
      )
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
      raise "Cannot pop messages, consumers not started" unless @consumers_started

      # Exit when we hit the job limit by sending SIGTERM to oneself.
      # This allows for everything to be cleaned up properly.
      if (@job_limit > 0) && (@job_count >= @job_limit)
        debug "Processed #{@job_count} jobs, sending TERM"
        Process.kill("TERM", Process.pid)
      end

      @job_count += 1

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
        response, headers, payload = @channel.basic_get(@queues[priority].name, :manual_ack => true)

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
      consumers = []
      consumer_thread_value = nil

      begin
        debug "[wait_for_message] setting up consumer, waiting for next message"

        # Setup a subscription to all the queues. The channel pre-fetch
        # will ensure we get exactly one message delivered
        PRIORITIES.each do |priority|
          consumers << @queues[priority].subscribe(:manual_ack => true) do |*args|
            @mutex.synchronize do
              consumer_thread_value = args
              @condvar.signal
            end
          end
        end
      rescue Exception => e
        consumers.each(&:cancel)
        @channel.nack(consumer_thread_value[0].delivery_tag, false, true) if consumer_thread_value
        raise
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
      consumers.each(&:cancel)

      # Return the message we got passed.
      TomQueue::Work.new(self, response, header, payload)
    end
  end
end
