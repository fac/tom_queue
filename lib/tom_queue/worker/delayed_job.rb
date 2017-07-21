require "tom_queue/stack"
require "tom_queue/errors"
require "tom_queue/persistence/model"

module TomQueue
  class Worker
    class DelayedJob < TomQueue::Stack::Layer
      include LoggingHelper

      # Public: Acquire a delayed job lock and pass on to the next layer. Passthru if this is not
      # a delayed job work object
      #
      # options - a Hash of options
      #   :work: - required. TomQueue::Work instance
      #   :worker: - required. TomQueue::Worker instance
      #
      # Returns boolean indicating job success
      def call(options)
        payload = deserialize(options[:work].payload)

        if delayed_job_payload?(payload)
          debug "[#{self.class.name}] Popped notification for #{payload["delayed_job_id"]}"
          process_delayed_job(payload, options)
        else
          # Not a delayed job, pass down the chain
          chain.call(options)
        end
      end

      private

      # Private: Safely deserialize the (presumed) JSON payload
      #
      # Returns the deserialized payload, or nil
      def deserialize(payload)
        JSON.load(payload)
      rescue
        nil
      end

      # Private: Is this a delayed job work unit?
      #
      # payload - the decoded message payload (Hash)
      #
      # Returns boolean
      def delayed_job_payload?(payload)
        payload && payload.has_key?("delayed_job_id")
      rescue
        false
      end

      # Private: Acquire a lock on the job and call the next step in the chain
      #
      # payload - the decoded message payload (Hash)
      # options - a hash of options for the job
      #
      # Returns the result of the chained call
      def process_delayed_job(payload, options)
        job = self.class.acquire_locked_job(payload, options)

        begin
          chain.call(options).tap do
            if !job.failed? || (job.failed? && Worker.destroy_failed_jobs)
              debug "[#{self.class.name}] Destroying #{job.id}"
              job.destroy
            end
          end
        rescue => ex
          worker = options[:worker]

          job.attempts += 1
          job.error = ex

          if job.attempts >= worker.max_attempts(job)
            worker.failed(job)
            raise TomQueue::PermanentError.new("Permanent Failure", options)
          else
            worker.class.lifecycle.run_callbacks(:error, worker, job) do
              job.run_at = job.reschedule_at
            end
            raise TomQueue::RepublishableError.new(ex.message, options)
          end
        end
      ensure
        if job && !job.destroyed?
          job.unlock
          job.save!
        end
      end

      # Private: Retrieves a job with a specific ID, acquiring a lock
      # preventing other concurrent workers from doing the same.
      #
      # Raises a TomQueue::DelayedJob::Error child exception if a lock cannot be acquired
      #
      # job_id - the ID of the job to acquire
      # digest - the expected digest of the job record
      # worker - the Delayed::Worker attempting to acquire the lock
      #
      # Returns a TomQueue::Persistence::Model instance or raises
      def self.acquire_locked_job(payload, options)
        job_id = payload['delayed_job_id']
        digest = payload['delayed_job_digest']
        # We have to be careful here, we grab the DJ lock inside a transaction that holds
        # a write lock on the record to avoid potential race conditions with other workers
        # doing the same...
        begin
          TomQueue::Persistence::Model.transaction do

            # Load the job, ensuring we have a write lock so other workers in the same position
            # block, avoiding race conditions
            job = options[:job] || TomQueue::Persistence::Model.where(id: job_id).lock(true).first

            options.merge!(job: job)

            if job.nil?
              raise TomQueue::DelayedJob::NotFoundError.new(
                "[#{self.name}] Received notification for non-existent job #{job_id}"
              )
            elsif job.failed?
              raise TomQueue::DelayedJob::FailedError.new(
                "[#{self.name}] Received notification for failed job #{job_id}",
                options
              )
            elsif job.locked?
              raise TomQueue::DelayedJob::LockedError.new(
                "[#{self.name}] Received notification for locked job #{job_id}",
                options.merge(run_at: job.locked_at + TomQueue::Worker.max_run_time + 1)
              )
            elsif digest && digest != job.digest
              raise TomQueue::DelayedJob::DigestMismatchError.new(
                "[#{self.name}] Digest mismatch for job #{job_id}",
                options
              )
            elsif !job.ready_to_run?
              raise TomQueue::DelayedJob::EarlyNotificationError.new(
                "[#{self.name}] Received early notification for job #{job_id}",
                options
              )
            end

            begin
              job.lock_with!(options[:worker].name)
              info "[#{self.name}] Acquired DB lock for job #{job_id}"
              job
            rescue => ex
              raise TomQueue::RetryableError.new(
                "[#{self.name}] Unknown error acquiring lock for job #{job_id}. #{ex.message}",
                options
              )
            end
          end
        end
      end
    end
  end
end
