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

    class DeferredWork < TomQueue::Work
      def initialize(deferred_manager, amqp_response, headers, payload)
        super(deferred_manager, amqp_response, headers, payload)
      end

      def run_at
        Time.at(headers[:headers]['run_at'])
      end

      def run_now?
        run_at < Time.now
      end

    end




    # Public: The queue / exchange name prefix used by this class
    #
    # Returns a string
    attr_reader :prefix

    # Public: The delegate of this class (i.e. where deferred messages are 
    #         published to)
    attr_reader :delegate

    # Public: Creates an instance (duh!?)
    #
    # prefix   - a string to prefix all AMQP queue / exchange names with
    # delegate - an object responding to #publish(<work>, {opts}) to dispatch
    #            deferred work to when it is ready to be run.
    #
    def initialize(prefix, delegate)
      @prefix = prefix
      @delegate = delegate
      @bunny = TomQueue.bunny

      @publisher_channel = @bunny.create_channel
      @publisher_mutex = Mutex.new


      # Setup the storage area for deferred work!    
      @deferred_messages = []
      @deferred_mutex = Mutex.new
      @deferred_condvar = ConditionVariable.new

      @deferred_thread = Thread.new(&method(:deferred_thread))
    end

    def queued_message(delivery, headers, payload)
      update_deferred! do
        work = DeferredWork.new(self, delivery, headers, payload)
        
        @deferred_messages << work
        @deferred_messages.sort! { |a, b| a.run_at.to_f <=> b.run_at.to_f }
      end
    rescue 
      puts $!.inspect
    end

    def deferred_thread
      # Create the necessary AMQP gubbins
      @channel = TomQueue.bunny.create_channel
      @channel.prefetch(0)
      
      # Creates a deferred exchange and queue
      @exchange = @channel.fanout("#{prefix}.work.deferred", :durable => true, :auto_delete => false)
      @queue = @channel.queue("#{prefix}.work.deferred", :durable => true, :auto_delete => false).bind(@exchange.name)

      # Subscribe to the queue immediately!
      @consumer = @queue.subscribe(:ack => true, &method(:queued_message))
      
      loop do
        @deferred_mutex.synchronize do
                    
          sleep_interval = if @deferred_messages.empty?
            60
          else
            @deferred_messages.first.run_at - Time.now  
          end

          if sleep_interval > 0
            @deferred_condvar.wait(@deferred_mutex, sleep_interval)
          end

          while @deferred_messages.first && @deferred_messages.first.run_now?
            message = @deferred_messages.shift
            message.headers[:headers].delete('run_at')
            @delegate.publish(message.payload, message.headers[:headers])
            @channel.ack(message.response.delivery_tag)
          end

        end
      end

    rescue
      p $!
      $!.backtrace.each {|l| puts "\t#{l}" }
    ensure
      @deferred_thread = nil
    end

    def update_deferred!
      @deferred_mutex.synchronize do

        # let our caller do something whilst we're holding onto the mutex
        yield

        # Signalling this will break out of the "sleep" above
        # early, causing the loop to spin
        @deferred_condvar.signal

      end
    end

    def purge!
      # Urgh, it's not as clean as just "purge" as, calling this will
      # get rid of the un-delivered messages, then we'll exit and the un-acked
      # messages will be re-queued.
      # So, first we need to explicitly ack any messages we're holding onto
      update_deferred! do
       while (message = @deferred_messages.pop)
         @channel.ack(message.response.delivery_tag)
       end
      end
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
      @publisher_mutex.synchronize do
        @publisher_channel.fanout("#{@prefix}.work.deferred", :passive=> true).publish(work, {
          :headers => opts.merge(:run_at => run_at.to_f)
        })
      end
    end

  end

end