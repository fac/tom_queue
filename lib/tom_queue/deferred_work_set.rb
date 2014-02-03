module TomQueue

  # Internal: This class wraps the pool of work items that are waiting for their run_at
  # time to be reached.
  #
  # It also incorporates the logic and coordination required to stall a thread until the
  # work is ready to run.
  #
  class DeferredWorkSet

    # Internal: A wrapper object to store the run at and the opaque work object inside the @work array.
    class Element < Struct.new(:run_at, :work)
      include Comparable

      # Internal: An integer version of run_at, less precise, but faster to compare.
      attr_reader :fast_run_at

      # Internal: Creates an element. This is called by DeferredWorkSet as work is scheduled so
      # shouldn't be done directly.
      #
      # run_at - (Time) the time when this job should be run
      # work   - (Object) a payload associated with this work. Just a plain ruby
      #          object that it is up to the caller to interpret
      #
      def initialize(run_at, work)
        super(run_at, work)
        @fast_run_at = (run_at.to_f * 1000).to_i
      end

      # Internal: Comparison function, referencing the scheduled run-time of the element
      #
      # NOTE: We don't compare the Time objects directly as this is /dog/ slow, as is comparing
      # float objects, and this function will be called a /lot/ - so we compare reasonably
      # accurate integer values created in the initializer.
      #
      def <=> (other)
        fast_run_at <=> other.fast_run_at
      end

      # Internal: We need to override this in order for elements with the same run_at not to be deleted
      # too soon.
      #
      # When #<=> is used with `Comparable`, we get #== for free, but when it operates using run_at, it has
      # the undesirable side-effect that when Array#delete is called with an element, all other elements with
      # the same run_at are deleted, too (since #== is used by Array#delete).
      #
      def == (other)
        false
      end
    end

    def initialize
      @mutex = Mutex.new
      @condvar = ConditionVariable.new
      @work = TomQueue::SortedArray.new
    end

    # Public: Returns the integer number of elements in the set
    #
    # Returns integer
    def size
      @work.size
    end

    # Public: Block the calling thread until some work is ready to run
    # or the timeout expires.
    #
    # This is intended to be called from a single worker thread, for the
    # time being, if you try and block on this method concurrently in
    # two threads, it will raise an exception!
    #
    # timeout - (Fixnum, seconds) how long to wait before timing out
    #
    # Returns previously scheduled work, or
    #         nil if the thread was interrupted or the timeout expired
    def pop(timeout)
      timeout_end = Time.now + timeout
      returned_work = nil

      @interrupt = false

      @mutex.synchronize do
        raise RuntimeError, 'DeferredWorkSet: another thread is already blocked on a pop' unless @blocked_thread.nil?

        begin
          @blocked_thread = Thread.current

          begin
            end_time = [next_run_at, timeout_end].compact.min
            delay = end_time - Time.now
            @condvar.wait(@mutex, delay) if delay > 0
          end while Time.now < end_time and @interrupt == false

          element = earliest_element
          if element && element.run_at < Time.now
            @work.delete(element)
            returned_work = element.work
          end

        ensure
          @blocked_thread = nil
        end
      end

      returned_work
    end

    # Public: Interrupt anything sleeping on this set
    #
    # This is "thread-safe" and is designed to be called from threads
    # to interrupt the work loop thread blocked on a pop.
    #
    def interrupt
      @mutex.synchronize do
        @interrupt = true
        @condvar.signal
      end
    end

    # Public: Add some work to the set
    #
    # This is "threa-safe" in that it can be (and is intended to
    # be) called from threads other than the one calling pop without
    # any additional synchronization.
    #
    # run_at - (Time) when the work is to be run
    # work   - the DeferredWork object
    #
    def schedule(run_at, work)
      @mutex.synchronize do
        yield if block_given?
        new_element = Element.new(run_at, work)
        @work << new_element
        @condvar.signal
      end
    end

    # Public: Returns the temporally "soonest" element in the set
    # i.e. the work that is next to be run
    #
    # Returns the work Object passed to schedule instance or
    #         nil if there is no work in the set
    def earliest
      e = earliest_element
      e && e.work
    end

    # Internal: The next time this thread should next wake up for an element
    #
    # If there are elements in the work set, this will correspond to time of the soonest.
    #
    # Returns a Time object, or nil if there are no elements stored.
    def next_run_at
      e = earliest_element
      e && e.run_at
    end

    # Internal: The Element object wrapping the work with the soonest run_at value
    #
    # Returns Element object, or nil if the work set is empty
    def earliest_element
      @work.first
    end
  end

end
