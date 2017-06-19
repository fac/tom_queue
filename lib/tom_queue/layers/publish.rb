require "tom_queue/delayed_job/external_messages"

module TomQueue
  module Layers
    class Publish < TomQueue::Stack::Layer
      include TomQueue::DelayedJob::ExternalMessages

      # Public: Push the work unit to the queue manager
      #
      # work - the work unit being enqueued
      # options - Hash of options defining how the job should be run
      #
      # Returns modified [work, options]
      def call(work, options)
        if work.is_a?(TomQueue::Persistence::Model)
          publish_delayed_job(work)
        else
          # TODO: Implement non DJ work
          raise "Unknown work type"
        end
        chain.call(work, options)
      end

      private

      # Private: The QueueManager instance
      #
      # Returns a memoized TomQueue::QueueManager
      def self.queue_manager
        @@tomqueue_manager ||= TomQueue::QueueManager.new.tap do |manager|
          setup_external_handler(manager)
        end
      end

      # Private: Publish the delayed job to the queue manager
      #
      # job - a persistence model instance
      # options - a Hash of options describing the work
      #
      # Returns nothing
      def publish_delayed_job(job)
        raise ArgumentError, "cannot publish an unsaved Delayed::Job object" if job.new_record?

        payload = JSON.dump({
          "delayed_job_id"         => job.id,
          "delayed_job_digest"     => job.digest,
          "delayed_job_updated_at" => job.updated_at.iso8601(0)
        })

        priority = TomQueue::DelayedJob.priority_map.fetch(job.priority, TomQueue::NORMAL_PRIORITY)

        self.class.queue_manager.publish(payload, run_at: job.run_at, priority: priority)
      end
    end
  end
end
