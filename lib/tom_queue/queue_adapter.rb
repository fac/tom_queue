# frozen_string_literal: true

module TomQueue
  class QueueAdapter
    def enqueue(job) #:nodoc:
      enqueue_at(job, Time.now)
    end

    def enqueue_at(job, timestamp) #:nodoc:
      delayed_job_fields = {
        queue: job.queue_name,
        priority: job.priority || 0,
        run_at: job.scheduled_at,
        payload_object: job,
      }

      Delayed::Job.new(delayed_job_fields).tap do |job|
        Delayed::Worker.lifecycle.run_callbacks(:enqueue, job) do
          p "payload_object is #{job.payload_object}"
          p "handler is: #{job.handler}"
          job.save
        end
      end
    end
  end
end

module ActiveJob
  module QueueAdapters
    TomQueueAdapter = TomQueue::QueueAdapter
  end
end
