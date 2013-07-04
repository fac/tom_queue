require 'active_support/concern'


module TomQueue
  module DelayedJobHook

    class AmqpConsumer < Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.after(:error) do |worker, job|
          job.tomqueue_publish if job.attempts <= worker.max_attempts(job)
        end

        lifecycle.after(:perform) do |worker, job|
          job.tomqueue_work && job.tomqueue_work.ack!
        end
      end
    end


    class Job < ::Delayed::Backend::ActiveRecord::Job

      # This is a reference to the TomQueue::Work object that triggered
      # this job
      attr_accessor :tomqueue_work

      after_create :tomqueue_publish

      # Map External priority values to the TomQueue priority levels
      cattr_reader :tomqueue_priority_map
      @@tomqueue_priority_map = Hash.new(TomQueue::NORMAL_PRIORITY)

      # Publish an AMQP message to trigger the job
      def tomqueue_publish
        self.class.tomqueue_manager.publish(JSON.dump({"delayed_job_id" => self.id}), {
          :run_at => self.run_at,
          :priority => self.class.tomqueue_priority_map.fetch(self.priority, TomQueue::NORMAL_PRIORITY)
        })
      end

      # Returns a shared instance of the QueueManager
      def self.tomqueue_manager
        @@tomqueue_manager ||= TomQueue::QueueManager.new
      end

      # This is called when a worker wants to reserve a single job
      # We pop a message off the AMQP queue; look up and return the
      # Delayed::Job instance from the database. And DJ is none the
      # wiser.
      def self.reserve(worker, max_run_time = ::Delayed::Worker.max_run_time)

        # Make sure we can stop a worker that is blocked on a pop
        Delayed::Worker.raise_signal_exceptions = true
        work = self.tomqueue_manager.pop
        Delayed::Worker.raise_signal_exceptions = false

        # Load up the job
        job = self.ready_to_run(worker.name, max_run_time).find_by_id(JSON.load(work.payload)['delayed_job_id'], :lock => true)
        if job
          job.update_attributes!({:locked_at => db_time_now, :locked_by => worker.name}, { :without_protection => true })
          job.tomqueue_work = work
        else
          work.ack!
        end

        job
      rescue
        puts "FAILED TO RESERVE JOB: #{$!.inspect}"
        work && work.ack!
      end
    end

    
  end
end