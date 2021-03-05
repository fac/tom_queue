# frozen_string_literal: true

module TomQueue
  class QueueAdapter
    def enqueue(job) #:nodoc:
      enqueue_at(job, Time.now)
    end

    def enqueue_at(job, timestamp) #:nodoc:
      Rails.logger.info("ENQUEING JOB ID #{job.provider_job_id}")
      delayed_job_fields = {
        queue: job.queue_name,
        priority: job.priority || 0,
        run_at: Time.at(timestamp),
        payload_object: job,
      }

      if job.delayed_job_record.present?
        Rails.logger.info("RE-ENQUEUING JOB: DELAYED_JOB_RECORD IS PRESENT, job is a #{job.class}, #{job.inspect}")
        job.delayed_job_record.update(run_at: timestamp, attempts: job.executions)
        # update job if provider_job_id set
      else
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
end

module ActiveJob
  module QueueAdapters
    TomQueueAdapter = TomQueue::QueueAdapter
  end
end
