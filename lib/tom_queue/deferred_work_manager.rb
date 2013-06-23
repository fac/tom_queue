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

      # Push this work on to the deferred queue

    end

  end

end