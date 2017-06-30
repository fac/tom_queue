require "tom_queue/delayed_job"

module TomQueue
  module Persistence
    # TODO: Remove the inheritance once the link to DJ has been killed
    class Model < ::Delayed::Job
      ENQUEUE_ATTRIBUTES = %i{priority run_at queue payload_object}

      self.table_name = :delayed_jobs

      # Public: Calculate a hexdigest of the attributes
      #
      # This is used to detect if the received message is stale, as it's
      # sent as part of the AMQP payload and then re-calculated when the
      # worker is about to run the job.
      #
      # Returns a string
      BROKEN_DIGEST_CLASSES = [DateTime, Time, ActiveSupport::TimeWithZone]
      def digest
        digest_string = attributes.map do |k,v|
          BROKEN_DIGEST_CLASSES.include?(v.class) ? [k,v.to_i] : [k,v.to_s]
        end.to_s
        Digest::MD5.hexdigest(digest_string)
      end

      # Public: Is this job ready to run?
      #
      # Returns boolean
      def ready_to_run?
        run_at <= self.class.db_time_now + 5
      end

      # Public: Lock the record using the given worker name
      #
      # worker_name - String
      #
      # Returns nothing
      def lock_with!(worker_name)
        self.locked_by = worker_name
        self.locked_at = self.class.db_time_now
        save!
      end

      # Public: is this job locked
      #
      # Returns boolean true if the job has been locked by a worker
      def locked?
        !!locked_by && !!locked_at && (locked_at + TomQueue::Worker.max_run_time) >= self.class.db_time_now
      end

      attr_reader :error
      def error=(error)
        @error = error
        self.last_error = "#{error.message}\n#{error.backtrace.join("\n")}"
      end

      # Public: We never want to publish this job using callbacks, and because
      # we inherit from Delayed::Job we need to prevent this for now.
      #
      # Returns boolean...
      def skip_publish
        true
      end
    end
  end
end
