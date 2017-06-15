module TomQueue
  module Persistence
    class Model < ActiveRecord::Base
      ENQUEUE_ATTRIBUTES = %i{priority handler run_at queue}

      self.table_name = :delayed_jobs

      before_save :set_default_run_at

      # Public: Calculate a hexdigest of the attributes
      #
      # This is used to detect if the received message is stale, as it's
      # sent as part of the AMQP payload and then re-calculated when the
      # worker is about to run the job.
      #
      # Returns a string
      BROKEN_DIGEST_CLASSES = [DateTime, Time, ActiveSupport::TimeWithZone]
      def digest
        digest_string = self.attributes.map { |k,v| BROKEN_DIGEST_CLASSES.include?(v.class) ? [k,v.to_i] : [k,v.to_s] }.to_s
        Digest::MD5.hexdigest(digest_string)
      end

      private

      def set_default_run_at
        self.run_at ||= self.class.db_time_now
      end

      # Get the current time (GMT or local depending on DB)
      # Note: This does not ping the DB to get the time, so all your clients
      # must have syncronized clocks.
      def self.db_time_now
        if Time.zone
          Time.zone.now
        elsif ::ActiveRecord::Base.default_timezone == :utc
          Time.now.utc
        else
          Time.now
        end
      end
    end
  end
end
