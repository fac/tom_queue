module TomQueue
  module Persistence
    class Model < ActiveRecord::Base
      self.table_name = :delayed_jobs

      before_save :set_default_run_at

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
