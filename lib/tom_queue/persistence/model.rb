module TomQueue
  module Persistence
    # TODO: Remove the inheritance once the link to DJ has been killed
    class Model < ::Delayed::Job
      ENQUEUE_ATTRIBUTES = %i{priority run_at queue}

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
