require 'tom_queue/work'
module TomQueue

  # Internal: This is an internal class that oversees the delay of "deferred"
  #  work, that is, work with a future :run_at value.
  #
  # This is created by, and associated with, a QueueManager object. The queue manager
  # pushes work into this method by calling the handle_deferred(...) method, and work
  # is passed back by simply calling the #publish(...) method on the QeueManager (which is
  # this classes delegate).
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


    # Public: Return a hash of all prefixed singledtons, keyed on the prefix
    #
    # This method really is just for testing convenience.
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
      channel.fanout("#{@prefix}.work.deferred", :passive => true).publish(work, {
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
      @thread = nil unless @thread && @thread.alive?
      @thread ||= Thread.new(&method(:thread_main))
    end

    # Public: Ensure the thread shuts-down and stops. Blocks until
    # the thread has actually shut down
    #
    def ensure_stopped
      if @thread
        @thread.kill
        @thread.join
      end
      @thread = nil
    end

    def purge!
      channel = TomQueue.bunny.create_channel
      channel.queue("#{prefix}.work.deferred", :passive => true).purge()
      channel.close
    rescue
    end


    ##### Thread Internals #####
    #
    # Cross this barrier with care :)
    #

    # Internal: The main loop of the thread
    #
    def thread_main
      # Create a dedicated channel, and ensure it's prefetch 
      # means we'll empty the queue
      channel = TomQueue.bunny.create_channel
      channel.prefetch(0)

      # Create an exchange and queue
      exchange = channel.fanout("#{prefix}.work.deferred", :durable => true, :auto_delete => false)
      queue = channel.queue("#{prefix}.work.deferred", :durable => true, :auto_delete => false).bind(exchange.name)

      deferred_set = DeferredWorkSet.new

      out_manager = QueueManager.new(prefix)

      # This block will get called-back for new messages
      consumer = queue.subscribe(:ack => true) do |response, headers, payload|
        run_at = Time.at(headers[:headers]['run_at'])
        deferred_set.schedule(run_at, [response, headers, payload])
      end

      loop do
        
        # This will block until work is ready to be returned, interrupt
        # or the 10-second timeout value.
        response, headers, payload = deferred_set.pop(10)
        puts "deferred set returned #{response}"

        if response
          headers[:headers].delete('run_at')
          out_manager.publish(payload, headers[:headers])
          channel.ack(response.delivery_tag)
        end

      end

    rescue
      puts "EXCEPTION IN DEFERRED THREAD"
      puts $!
    end

  end

end



#   class DeferredWorkManager

#     class DeferredWork < TomQueue::Work
#       def initialize(deferred_manager, amqp_response, headers, payload)
#         super(deferred_manager, amqp_response, headers, payload)
#       end

#       def run_at
#         Time.at(headers[:headers]['run_at'])
#       end

#       def run_now?
#         run_at < Time.now
#       end

#     end




#     # Public: The queue / exchange name prefix used by this class
#     #
#     # Returns a string
#     attr_reader :prefix

#     # Public: The delegate of this class (i.e. where deferred messages are 
#     #         published to)
#     attr_reader :delegate

#     # Public: Creates an instance (duh!?)
#     #
#     # prefix   - a string to prefix all AMQP queue / exchange names with
#     # delegate - an object responding to #publish(<work>, {opts}) to dispatch
#     #            deferred work to when it is ready to be run.
#     #
#     def initialize(prefix, delegate)
#       @prefix = prefix
#       @delegate = delegate
#       @bunny = TomQueue.bunny

#       @publisher_channel = @bunny.create_channel
#       @publisher_mutex = Mutex.new


#       # Setup the storage area for deferred work!    
#       @deferred_messages = []
#       @deferred_mutex = Mutex.new
#       @deferred_condvar = ConditionVariable.new

#       @deferred_thread = Thread.new(&method(:deferred_thread))
#     end

#     def queued_message(delivery, headers, payload)
#       update_deferred! do
#         work = DeferredWork.new(self, delivery, headers, payload)
        
#         @deferred_messages << work
#         @deferred_messages.sort! { |a, b| a.run_at.to_f <=> b.run_at.to_f }
#       end
#     rescue 
#       puts $!.inspect
#     end

#     def deferred_thread
#       # Create the necessary AMQP gubbins
#       @channel = TomQueue.bunny.create_channel
#       @channel.prefetch(0)
      
#       # Creates a deferred exchange and queue
#       @exchange = @channel.fanout("#{prefix}.work.deferred", :durable => true, :auto_delete => false)
#       @queue = @channel.queue("#{prefix}.work.deferred", :durable => true, :auto_delete => false).bind(@exchange.name)

#       # Subscribe to the queue immediately!
#       @consumer = @queue.subscribe(:ack => true, &method(:queued_message))
      
#       loop do
#         @deferred_mutex.synchronize do
                    
#           sleep_interval = if @deferred_messages.empty?
#             60
#           else
#             @deferred_messages.first.run_at - Time.now  
#           end

#           if sleep_interval > 0
#             @deferred_condvar.wait(@deferred_mutex, sleep_interval)
#           end

#           while @deferred_messages.first && @deferred_messages.first.run_now?
#             message = @deferred_messages.shift
#             message.headers[:headers].delete('run_at')
#             @delegate.publish(message.payload, message.headers[:headers])
#             @channel.ack(message.response.delivery_tag)
#           end

#         end
#       end

#     rescue
#       p $!
#       $!.backtrace.each {|l| puts "\t#{l}" }
#     ensure
#       @deferred_thread = nil
#     end

#     def update_deferred!
#       @deferred_mutex.synchronize do

#         # let our caller do something whilst we're holding onto the mutex
#         yield

#         # Signalling this will break out of the "sleep" above
#         # early, causing the loop to spin
#         @deferred_condvar.signal

#       end
#     end

#     def purge!
#       # Urgh, it's not as clean as just "purge" as, calling this will
#       # get rid of the un-delivered messages, then we'll exit and the un-acked
#       # messages will be re-queued.
#       # So, first we need to explicitly ack any messages we're holding onto
#       update_deferred! do
#        while (message = @deferred_messages.pop)
#          @channel.ack(message.response.delivery_tag)
#        end
#       end
#     end


#   end

# end