require 'active_record'

module TomQueue
  module Persistence
    # TODO: Remove the inheritance once the link to DJ has been killed
    class Model < ::ActiveRecord::Base
      attr_accessor :skip_publish

      before_save :set_default_run_at
      after_commit -> { TomQueue::Enqueue::Publish.after_commit }
      after_rollback -> { TomQueue::Enqueue::Publish.after_rollback }

      ENQUEUE_ATTRIBUTES = %i{priority run_at queue payload_object attempts}

      self.table_name = :delayed_jobs

      def self.ready_to_run(worker_name, max_run_time)
        where("(run_at <= ? AND (locked_at IS NULL OR locked_at < ?) OR locked_by = ?) AND failed_at IS NULL", db_time_now, db_time_now - max_run_time, worker_name)
      end

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

      # Public: The AMQP payload for this job
      #
      # Returns a JSON string
      def payload
        JSON.dump({
          "delayed_job_id"         => id,
          "delayed_job_digest"     => digest,
          "delayed_job_updated_at" => updated_at.iso8601(0)
        })
      end

      def payload_object=(object)
        @payload_object = object
        self.handler = object.to_yaml
      end

      def payload_object
        @payload_object ||= YAML.load_dj(handler)
      rescue TypeError, LoadError, NameError, ArgumentError, SyntaxError, Psych::SyntaxError => e
        raise DeserializationError, "Job failed to load: #{e.message}. Handler: #{handler.inspect}"
      end

      def hook(name, *args)
        if payload_object.respond_to?(name)
          method = payload_object.method(name)
          method.arity == 0 ? method.call : method.call(self, *args)
        end
      rescue DeserializationError # rubocop:disable HandleExceptions
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

      ParseObjectFromYaml = %r{\!ruby/\w+\:([^\s]+)} # rubocop:disable ConstantName

      def name
        @name ||= payload_object.respond_to?(:display_name) ? payload_object.display_name : payload_object.class.name
      rescue DeserializationError
        ParseObjectFromYaml.match(handler)[1]
      end


      attr_reader :error
      def error=(error)
        @error = error
        self.last_error = "#{error.message}\n#{error.backtrace.join("\n")}"
      end

      def invoke_job
        TomQueue::Worker.lifecycle.run_callbacks(:invoke_job, self) do
          begin
            hook :before
            payload_object.perform
            hook :success
          rescue => e
            hook :error, e
            raise e
          ensure
            hook :after
          end
        end
      end

      def failed?
        !!failed_at
      end
      alias_method :failed, :failed?

      # Unlock this job (note: not saved to DB)
      def unlock
        self.locked_at    = nil
        self.locked_by    = nil
      end

      def reschedule_at
        if payload_object.respond_to?(:reschedule_at)
          payload_object.reschedule_at(self.class.db_time_now, attempts)
        else
          self.class.db_time_now + (attempts**4) + 5
        end
      end

      def max_attempts
        payload_object.max_attempts if payload_object.respond_to?(:max_attempts)
      end

      def max_run_time
        return unless payload_object.respond_to?(:max_run_time)
        return unless (run_time = payload_object.max_run_time)

        if run_time > Delayed::Worker.max_run_time
          Delayed::Worker.max_run_time
        else
          run_time
        end
      end

      def fail!
        update_attributes(:failed_at => self.class.db_time_now)
      end

      private

      def publish
        TomQueue::Enqueue::Publish.after_commit
      end

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
