module Delayed
  module Backend
    module Base
      def self.included(base)
        base.extend ClassMethods
      end

      # ActiveJob that we're wrapping DelayedJobs in
      class DelayedWrapperJob < ActiveJob::Base
        def self.wrap_payload_object(payload_object)
          new(Marshal.dump(payload_object))
        end

        def perform(payload_object_string)
          Marshal.load(payload_object_string).perform
        end
      end

      module ClassMethods
        def enqueue(payload = nil, payload_object: nil, queue: nil, priority: nil, run_at: nil)
          payload_object ||= payload
          queue ||= payload_object.respond_to?(:queue_name) ? payload_object.queue_name : Delayed::Worker.default_queue_name

          if queue_attribute = Delayed::Worker.queue_attributes[queue]
            priority ||= queue_attribute.fetch(:priority) { Delayed::Worker.default_priority }
          end

          DelayedWrapperJob.wrap_payload_object(payload_object).enqueue(
            queue: queue,
            priority: priority,
            wait_until: run_at,
          )
        end

        def enqueue_job(options)
          p "Hiya, we're enqueuing the job!"
          Rails.logger.info("IN ENQUEUE")
          new(options).tap do |job|
            Delayed::Worker.lifecycle.run_callbacks(:enqueue, job) do
              job.hook(:enqueue)
              Delayed::Worker.delay_job?(job) ? job.save : job.invoke_job
            end
          end
        end

        def reserve(worker, max_run_time = Worker.max_run_time)
          # We get up to 5 jobs from the db. In case we cannot get exclusive access to a job we try the next.
          # this leads to a more even distribution of jobs across the worker processes
          find_available(worker.name, worker.read_ahead, max_run_time).detect do |job|
            job.lock_exclusively!(max_run_time, worker.name)
          end
        end

        # Allow the backend to attempt recovery from reserve errors
        def recover_from(_error); end

        # Hook method that is called before a new worker is forked
        def before_fork; end

        # Hook method that is called after a new worker is forked
        def after_fork; end

        def work_off(num = 100)
          warn '[DEPRECATION] `Delayed::Job.work_off` is deprecated. Use `Delayed::Worker.new.work_off instead.'
          Delayed::Worker.new.work_off(num)
        end
      end

      attr_reader :error
      def error=(error)
        @error = error
        self.last_error = "#{error.message}\n#{error.backtrace.join("\n")}" if respond_to?(:last_error=)
      end

      def failed?
        !!failed_at
      end
      alias_method :failed, :failed?

      ParseObjectFromYaml = %r{\!ruby/\w+\:([^\s]+)} # rubocop:disable ConstantName

      def name
        @name ||= payload_object.respond_to?(:display_name) ? payload_object.display_name : payload_object.class.name
      rescue DeserializationError
        p "Oops. Couldn't deserialize name"
        ParseObjectFromYaml.match(handler)[1]
      end

      def payload_object=(object)
        @payload_object = object
        #byebug
        self.handler = object.serialize # this is a hash #Marshal.dump(object)
        Rails.logger.info("HANDLER IS :#{handler}")
        self.handler
      end

      def payload_object
        @payload_object ||= ActiveJob::Base.deserialize(handler)
      end

      def invoke_job
        Delayed::Worker.lifecycle.run_callbacks(:invoke_job, self) do
          begin
            hook :before
            ActiveJob::Callbacks.run_callbacks(:execute) do
              payload_object.perform_now
            end
            hook :success
          rescue Exception => e # rubocop:disable RescueException
            hook :error, e
            raise e
          ensure
            hook :after
          end
        end
      end

      # Unlock this job (note: not saved to DB)
      def unlock
        self.locked_at    = nil
        self.locked_by    = nil
      end

      def hook(name, *args)
        if payload_object.respond_to?(name)
          method = payload_object.method(name)
          method.arity.zero? ? method.call : method.call(self, *args)
        end
      rescue DeserializationError # rubocop:disable HandleExceptions
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

      def destroy_failed_jobs?
        payload_object.respond_to?(:destroy_failed_jobs?) ? payload_object.destroy_failed_jobs? : Delayed::Worker.destroy_failed_jobs
      rescue DeserializationError
        Delayed::Worker.destroy_failed_jobs
      end

      def fail!
        self.failed_at = self.class.db_time_now
        save!
      end

    protected

      def set_default_run_at
        self.run_at ||= self.class.db_time_now
      end

      # Call during reload operation to clear out internal state
      def reset
        @payload_object = nil
      end
    end
  end
end
