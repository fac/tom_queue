require "tom_queue/stack"
require "tom_queue/persistence/model"

module TomQueue
  module Layers
    class JobLocking < TomQueue::Stack::Layer
      include LoggingHelper

      # Public: Acquire a delayed job lock and pass on to the next layer. Passthru if this is not
      # a delayed job work object
      #
      # work - a TomQueue::Work instance
      # options - a Hash of options
      #   :worker: - required. TomQueue::Worker instance
      #
      # Returns [result, options]
      def call(work, options)
        payload = JSON.load(work.payload)

        if delayed_job_payload?(payload)
          debug "[#{self.class.name}] Popped notification for #{payload["delayed_job_id"]}"
          with_locked_job(work, payload, options) do |job|
            chain.call(job, options)
          end
        else
          chain.call(work, options)
        end

      rescue JSON::ParserError => e
        work.ack!
        error "[#{self.class.name}] Failed to parse JSON payload: #{e.message}. Dropping AMQP message."

        TomQueue.exception_reporter && TomQueue.exception_reporter.notify(e)

        [false, options]
      end

      def with_locked_job(work, payload, options, &block)
        job_id = payload['delayed_job_id']
        digest = payload['delayed_job_digest']

        locked_job = self.class.acquire_locked_job(job_id, options[:worker]) do |job|
          digest.nil? || job.digest == digest
        end

        if locked_job
          info "[#{self.class.name}] Acquired DB lock for job #{job_id}"
          yield locked_job
        else
          work.ack!
        end
      end

      private

      def delayed_job_payload?(payload)
        payload.has_key?("delayed_job_id")
      rescue
        false
      end

      # Private: Republish a job onto the queue
      #
      # job - a TomQueue::Persistence::Model instance
      # options - a Hash of options
      #   :run_at: - the time to requeue the message for (optional)
      #
      # Returns nothing
      def self.republish(job, options)
        @@republisher ||= Publish.new
        @@republisher.call(job, options)
      end

      # Private: Retrieves a job with a specific ID, acquiring a lock
      # preventing other concurrent workers from doing the same.
      #
      # job_id - the ID of the job to acquire
      # worker - the Delayed::Worker attempting to acquire the lock
      # block  - if provided, it is yeilded with the job object as the only argument
      #          whilst the job record is locked.
      #          If the block returns true, the lock is acquired.
      #          If the block returns false, the call will return nil
      #
      # NOTE: when a job has a stale lock, the block isn't yielded, as it is presumed
      #       the job has stared somewhere and crashed out - so we just return immediately
      #       as it will have previously passed the validity check (and may have changed since).
      #
      # Returns * a TomQueue::Persistence::Model instance if the job was found and lock acquired
      #         * nil if the job wasn't found, has failed, is locked, or is early
      def self.acquire_locked_job(job_id, worker)
        # We have to be careful here, we grab the DJ lock inside a transaction that holds
        # a write lock on the record to avoid potential race conditions with other workers
        # doing the same...
        begin
          TomQueue::Persistence::Model.transaction do

            # Load the job, ensuring we have a write lock so other workers in the same position
            # block, avoiding race conditions
            job = TomQueue::Persistence::Model.where(id: job_id).lock(true).first

            if job.nil?
              warn "[#{self.name}] Received notification for non-existent job #{job_id}"
            elsif job.failed?
              warn "[#{self.name}] Received notification for failed job #{job.id}"
            elsif job.locked?
              # We schedule another AMQP message to arrive when the job's lock will have expired.
              retry_at = job.locked_at + worker.max_run_time(job) + 1
              warn "[#{self.class.name}] Received notification for locked job #{job.id}, will schedule follow up at #{retry_at}"
              republish(job, run_at: retry_at)
            elsif job.locked_at || job.locked_by || (!block_given? || yield(job) == true)
              if job.ready_to_run?
                return job.lock_with!(worker.name)
              else
                warn "[#{self.name}] Received early notification for job #{job.id} - expected at #{job.run_at}"
                republish(job)
              end
            end

            nil
          end
        end
      end
    end
  end
end
