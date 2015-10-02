module TomQueue
  module Deferred
    class Work
      include Comparable

      attr_accessor :run_at, :job

      def initialize(run_at, job)
        # Convert time object to integer for faster comparsion
        @run_at = run_at.to_f
        @job = job
      end

      # In DeferredWorkManager we use SortedSet to maintain a priority queue of the jobs.
      # We redefine <=> operator for SortedSet to sort jobs by run_at.
      # However we don't want jobs with the same run_at time to be considered duplicates and not added to the set
      # or deleted with another element by accident.
      # So if run_at of the element matches with another element we compare them by object_id to consider them not equal
      def <=> (other)
        if run_at != other.run_at
          run_at <=> other.run_at
        else
          object_id <=> other.object_id
        end
      end
    end
  end
end
