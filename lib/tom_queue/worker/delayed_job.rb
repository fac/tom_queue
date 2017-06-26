require "tom_queue/stack"
require "tom_queue/delayed_job/errors"
require "tom_queue/persistence/model"

module TomQueue
  class Worker
    class DelayedJob < TomQueue::Stack::Layer
      include LoggingHelper

      # Public: Acquire a delayed job lock and pass on to the next layer. Passthru if this is not
      # a delayed job work object
      #
      # work - a TomQueue::Work instance
      # options - a Hash of options
      #   :worker: - required. TomQueue::Worker instance
      #
      # Returns [result, options] (bool, Hash)
      def call(work, options)
        payload = JSON.load(work.payload)

        if delayed_job_payload?(payload)
          debug "[#{self.class.name}] Popped notification for #{payload["delayed_job_id"]}"
          process_delayed_job(payload, options.merge(work: work))
        else
          # Not a delayed job, pass down the chain
          chain.call(work, options)
        end

      rescue JSON::ParserError => e
        TomQueue.exception_reporter && TomQueue.exception_reporter.notify(e)

        raise TomQueue::DelayedJob::DeserializationError,
          "[#{self.class.name}] Failed to parse JSON payload: #{e.message}. Dropping AMQP message"
      end

      private

      # Private: Is this a delayed job work unit?
      #
      # payload - the decoded message payload (Hash)
      #
      # Returns boolean
      def delayed_job_payload?(payload)
        payload.has_key?("delayed_job_id")
      rescue
        false
      end

      # Private: Acquire a lock on the job and call the next step in the chain
      #
      # payload - the decoded message payload (Hash)
      # options - a hash of options for the job
      #
      # Returns [result, options] (bool, Hash)
      def process_delayed_job(payload, options)
        job_id = payload['delayed_job_id']
        digest = payload['delayed_job_digest']

        job = self.class.acquire_locked_job(job_id, digest, options[:worker])

        begin
          job.lifecycle.hook(:before)
          chain.call(job, options).tap do
            job.lifecycle.hook(:success)
            job.destroy
          end
        rescue => ex
          job.error = ex
          job.save
          job.lifecycle.hook(:error, ex)
          raise ex
        end

      ensure
        if job
          job.lifecycle.hook(:after)
          job.unlock! unless job.destroyed?
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
      # Returns a TomQueue::Persistence::Model instance
      def self.acquire_locked_job(job_id, digest, worker)
        # We have to be careful here, we grab the DJ lock inside a transaction that holds
        # a write lock on the record to avoid potential race conditions with other workers
        # doing the same...
        begin
          TomQueue::Persistence::Model.transaction do

            # Load the job, ensuring we have a write lock so other workers in the same position
            # block, avoiding race conditions
            job = TomQueue::Persistence::Model.where(id: job_id).lock(true).first

            if job.nil?
              raise TomQueue::DelayedJob::NotFoundError.new(
                "[#{self.name}] Received notification for non-existent job #{job_id}"
              )
            elsif job.failed?
              raise TomQueue::DelayedJob::FailedError.new(
                "[#{self.name}] Received notification for failed job #{job_id}",
                job
              )
            elsif job.locked?
              raise TomQueue::DelayedJob::LockedError.new(
                "[#{self.name}] Received notification for locked job #{job_id}",
                job
              )
            elsif digest && digest != job.digest
              raise TomQueue::DelayedJob::DigestMismatchError.new(
                "[#{self.name}] Digest mismatch for job #{job_id}",
                job
              )
            elsif !job.ready_to_run?
              raise TomQueue::DelayedJob::EarlyNotificationError.new(
                "[#{self.name}] Received early notification for job #{job_id}",
                job
              )
            end

            begin
              job.lock_with!(worker.name)
              info "[#{self.name}] Acquired DB lock for job #{job_id}"
              job
            rescue => ex
              raise TomQueue::DelayedJob::Error, "[#{self.name}] Unknown error acquiring lock for job #{job_id}. #{ex.message}"
            end
          end
        end
      end

      def max_attempts(job)
        job.respond_to?(:max_attempts) ? job.max_attempts : TomQueue::Worker.max_attempts
      end
    end
  end
end
