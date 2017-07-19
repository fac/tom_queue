require "tom_queue/external_messages"

module TomQueue
  module Enqueue
    class Publish < TomQueue::Stack::Layer
      include LoggingHelper
      include TomQueue::DelayedJob::ExternalMessages

      # Public: Array of messages for uncommitted ActiveRecord jobs awaiting publishing once the
      # database is committed
      #
      # Returns Array
      def self.uncommitted
        @@uncommitted ||= []
      end

      # Public: Callback to be run after the jobs have been committed to push the messages to
      # RabbitMQ
      #
      # Returns nothing
      def self.after_commit
        while args = uncommitted.shift
          queue_manager.publish(*args)
        end
      end

      # Public: Push the work unit to the queue manager
      #
      # work - the work unit being enqueued
      # options - Hash of options defining how the job should be run
      #
      # Returns modified [work, options]
      def call(work, options)
        if work.is_a?(TomQueue::Persistence::Model)
          publish_delayed_job(work, options)
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
      def publish_delayed_job(job, options)
        return if job.skip_publish
        raise ArgumentError, "cannot publish an unsaved Delayed::Job object" if job.new_record?
        run_at = options[:run_at] || job.run_at

        debug "[#{self.class.name}] Pushing notification for #{job.id} to run in #{(run_at - Time.now).round(2)}"

        priority = TomQueue.priority_map.fetch(job.priority, TomQueue::NORMAL_PRIORITY)

        if ActiveRecord::Base.connection.transaction_open?
          self.class.uncommitted << [job.payload, run_at: run_at, priority: priority]
        else
          self.class.queue_manager.publish(job.payload, run_at: run_at, priority: priority)
        end
      end
    end
  end
end
