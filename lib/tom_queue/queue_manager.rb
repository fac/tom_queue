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

      @queue = []

      @mutex = Mutex.new
      @condvar = ConditionVariable.new
    end

    # Public: Purges all messages from queues. Dangerous!
    #
    # Please don't routinely use this, it's more a convenience 
    # function for tests to provide a blank slate
    #
    def purge!
      @mutex.synchronize {
        @queue = []
      }
    end


    # Public: Publish some work to the queue
    #
    # work - a serializable (to JSON) object representing the work
    #        please don't pass crazy objects like ActiveRecord instances, etc.
    #
    # Returns nil
    def publish(work)
      @mutex.synchronize {
        @queue.unshift(work)
        @condvar.signal
      }
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
      work = @mutex.synchronize { 
        @condvar.wait(@mutex) if opts.fetch(:block, true) && @queue.empty?
        @queue.pop
      }

      work && TomQueue::Work.new(work)
    end
    
  end

end