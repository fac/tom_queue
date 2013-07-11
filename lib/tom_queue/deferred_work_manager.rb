require 'tom_queue/work'
module TomQueue

  # Internal: This is an internal class that oversees the delay of "deferred"
  #  work, that is, work with a future :run_at value.
  #
  # There is a singleton object for each prefix value (really, there should only be a single
  # prefix used. The queue manager ensures this thread is running whenever #pop is called.
  # Work is also pushed to this maanger by the QueueManager when it needs to be deferred.
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

    # Public: Scoped singleton accessor
    #
    # This returns the shared work manager instance, creating it if necessary.
    #
    # Returns a DeferredWorkManager instance
    @@singletons_mutex = Mutex.new
    @@singletons = {}
    def self.instance(prefix = nil)
      prefix ||= TomQueue.default_prefix
      prefix || raise(ArgumentError, 'prefix is required')

      @@singletons_mutex.synchronize { @@singletons[prefix] ||= self.new(prefix) }
    end


    # Public: Return a hash of all prefixed singletons, keyed on their prefix
    #
    # This method really is just a convenience method for testing.
    #
    # NOTE: The returned hash is both a dupe and frozen, so should be safe to 
    # iterate and mutate instances.
    # 
    # Returns: { "prefix" => DeferredWorkManager(prefix),  ... }
    def self.instances
      @@singletons.dup.freeze
    end

    # Public: Shutdown all managers and wipe the singleton objects.
    # This method is really just a hook for testing convenience.
    #
    # Returns nil
    def self.reset!
      @@singletons_mutex.synchronize do
        @@singletons.each_pair do |k,v|
          v.ensure_stopped
        end
        @@singletons = {}
      end
      nil
    end

    # Public: Return the AMQP prefix used by this manager
    #
    # Returns string
    attr_reader :prefix

    # Internal: Creates the singleton instance, please use the singleton accessor!
    #
    # prefix - the AMQP prefix for this instance
    #
    def initialize(prefix)
      @prefix = prefix
      @thread = nil
    end

    # Public: Handle a deferred message
    #
    # work - (String) the work payload
    # opts - (Hash) the options of the message. See QueueManager#publish, but must include:
    #   :run_at = (Time) when the work should be run
    #
    def handle_deferred(work, opts)
      run_at = opts[:run_at]
      raise ArgumentError, 'work must be a string' unless work.is_a?(String)
      raise ArgumentError, ':run_at must be specified' if run_at.nil?
      raise ArgumentError, ':run_at must be a Time object if specified' unless run_at.is_a?(Time)

      # Push this work on to the deferred exchange
      channel = TomQueue.bunny.create_channel
      channel.fanout("#{@prefix}.work.deferred", :durable => true, :auto_delete => false).publish(work, {
          :headers => opts.merge(:run_at => run_at.to_f)
        })
      channel.close
    end

    # Public: Return the Thread associated with this manager
    #
    # Returns Ruby Thread object, or nil if it's not running
    attr_reader :thread
    
    # Public: Ensure the thread is running, starting if necessary
    #
    def ensure_running
      @thread_shutdown = false
      @thread = nil unless @thread && @thread.alive?
      @thread ||= Thread.new(&method(:thread_main))
    end

    # Public: Ensure the thread shuts-down and stops. Blocks until
    # the thread has actually shut down
    #
    def ensure_stopped
      if @thread
        @thread_shutdown = true
        @deferred_set && @deferred_set.interrupt
        @thread.join
      end
    end

    def purge!
      channel = TomQueue.bunny.create_channel
      channel.queue("#{prefix}.work.deferred", :passive => true).purge()
      channel.close
    rescue Bunny::NotFound
    end


    ##### Thread Internals #####
    #
    # Cross this barrier with care :)
    #

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
    def thread_consumer_callback(response, headers, payload)
      # Extract when we want to run this
      run_at = Time.at(headers[:headers]['run_at'])

      # schedule it in the work set
      @deferred_set.schedule(run_at, [response, headers, payload])
    rescue Exception => e
      r = TomQueue.exception_reporter
      r && r.notify(e)
      
      ### Avoid tight spinning workers by not re-queueing redlivered messages more than once!
      response.channel.reject(response.delivery_tag, !response.redelivered?)
    end


    # Internal: The main loop of the thread
    #
    def thread_main

      # Make sure we're low priority!
      Thread.current.priority = -10

      # Create a dedicated channel, and ensure it's prefetch 
      # means we'll empty the queue
      @channel = TomQueue.bunny.create_channel
      @channel.prefetch(0)

      # Create an exchange and queue
      exchange = @channel.fanout("#{prefix}.work.deferred", 
          :durable     => true,
          :auto_delete => false)

      queue = @channel.queue("#{prefix}.work.deferred",
          :durable     => true,
          :auto_delete => false).bind(exchange.name)

      
      @deferred_set = DeferredWorkSet.new
      
      @out_manager = QueueManager.new(prefix)

      # This block will get called-back for new messages
      consumer = queue.subscribe(:ack => true, &method(:thread_consumer_callback)) 

      # This is the core event loop - we block on the deferred set to return messages
      # (which have been scheduled by the AMQP consumer). If a message is returned
      # then we re-publish the messages to our internal QueueManager and ack the deferred
      # message
      until @thread_shutdown
        
        # This will block until work is ready to be returned, interrupt
        # or the 10-second timeout value.
        response, headers, payload = @deferred_set.pop(2)

        if response
          headers[:headers].delete('run_at')
          @out_manager.publish(payload, headers[:headers])
          @channel.ack(response.delivery_tag)
        end
      end

      consumer.cancel

    rescue
      reporter = TomQueue.exception_reporter
      reporter && reporter.notify($!)

    ensure
      @channel && @channel.close
      @deferred_set = nil
      @thread = nil      
    end

  end

end
