require 'active_support/concern'


module TomQueue
  module DelayedJobHook

    # This is our wrapper for Delayed::Job (ActiveRecord) which augments the 
    # save operations with AMQP notifications and replaces the reserve method
    # with a blocking AMQP pop operation.
    #
    # Since we want to retain the behaviour of Delayed::Job we over publish
    # messages and work out if a job is ready to run in the reserve method.
    #
    # In order to prevent the worker considering stale job states, we attach
    # two pieces of information, the job ID, so the job can be located and the 
    # updated_at timestamp when the notification is published.
    #
    # This means that the worker can simply load a job and, if a record is returned
    # quickly drop the notification if the updated_at value has changed since the
    # message was published. Another notification will likely be en-route.
    #
    # Cases to consider:
    #
    #   - after the commit of a transaction creating a job, we publish
    #     a message. We do this after commit as we want to make sure the
    #     worker considers the job when it has hit stable storage and will be 
    #     found.
    #
    #   - after the commit of a tx updating a job, we also publish.
    #     consider the scenario, job is created to run tomorrow, then updated
    #     to run in an hour. The first message will only get to the worker
    #     tomorrow, so we publish a second message to arrive in an hour and 
    #     know the worker will disregard the message that arrives tomorrow.
    #
    #   - rather than leaving the job un-acked for the duration of the process, we
    #     load the job, lock it and then re-publish a message that will trigger
    #     a worker after the maximum run duration. This will likely just be dropped
    #     since the job will have run successfully and been deleted, but equally could
    #     catch a job that has crashed the worker. This ties into the behaviour of DJ
    #     more closely than leaving the job un-acked.
    #
    # During the worker reserve method, we do a number of things:
    #
    #  - look up the job by ID, using the ready_to_run scope. We do this 
    #    with a pessimistic lock for update, so concurrent workers block.
    #
    #  - if there is no record, we ack the AMQP message and do nothing.
    #
    #  - if there is a record, we lock the job with our worker and save it.
    #    (releasing the lock) At this point, concurrent workers won't find the job
    #    as it has been DJ locked by this worker (so won't appear in the ready_to_run
    #    scope).
    #
    #  - we re-publish the job to arrive after the maximum work duration.
    #
    #  - then the message is acked on the RMQ server (if it fails from this point on, 
    #    DJ will pick it up after the maximum work duration)
    #
    class Job < ::Delayed::Backend::ActiveRecord::Job

      # Public: This provides a shared queue manager object, instantiated on the first 
      # call
      #
      # Returns a TomQueue::QueueManager instance
      def self.tomqueue_manager
        @@tomqueue_manager ||= TomQueue::QueueManager.new
      end

      # Map External priority values to the TomQueue priority levels
      cattr_reader :tomqueue_priority_map
      @@tomqueue_priority_map = Hash.new(TomQueue::NORMAL_PRIORITY)

      # Public: This calls #tomqueue_publish on all jobs currently
      # in the delayed_job table. This will probably end up with 
      # duplicate messages, but the worker should do the right thing
      #
      # Jobs should automatically publish themselves, so you should only
      # need to call this if you think TomQueue is misbehaving, or you're 
      # re-populating an empty queue server.
      #
      # Returns nil
      def self.tomqueue_republish

      end

      # This triggers the publish whenever a record is saved (and committed to
      # stable storage).
      #
      # It's also worth noting that after_commit masks exceptions, so a failed
      # publish won't bring down the caller.
      #
      after_commit :tomqueue_publish, :if => :persisted?

      # Public: Send a notification to a worker to consider this job, 
      # via AMQP. This is called automatically when a job is created
      # or updated (so you shouldn't need to call it directly unless
      # you believe TomQueue is misbehaving)
      #
      # deliver_at - when this message should be delivered.
      #              (Optional, defaults to the job's run_at time)
      #
      # Returns nil
      def tomqueue_publish(custom_run_at=nil)
        raise ArgumentError, "cannot publish an unsaved Delayed::Job object" if new_record?

        self.class.tomqueue_manager.publish(JSON.dump({
          "delayed_job_id" => self.id,
          "updated_at"     => self.updated_at.iso8601(0)
        }), {
          :run_at   => custom_run_at || self.run_at,
          :priority => self.class.tomqueue_priority_map.fetch(self.priority, TomQueue::NORMAL_PRIORITY)
        })
      rescue Exception => e
        r = TomQueue.exception_reporter
        r && r.notify(e)
        
        #TODO: Write error to the log!!
        
        raise
      end


      # Public: Called by Delayed::Worker to retrieve the next job to process
      #
      # This is the glue beween TomQueue and DelayedJob and implements most of
      # the behaviour discussed above.
      #
      # This function will block until a job becomes available to process. It tweaks
      # the `Delayed::Worker.raise_signal_exceptions` during the blocking stage so
      # the process can be interrupted.
      #
      # Returns Delayed::Job instance for the next job to process.
      def self.reserve(worker, max_run_time = Delayed::Worker.max_run_time)




      end

    end
  end
end



# Job is created - message published
# Job is updated
#



#     class AmqpConsumer < Delayed::Plugin
#       callbacks do |lifecycle|
#         lifecycle.after(:error) do |worker, job|
#           job.tomqueue_publish if job.attempts <= worker.max_attempts(job)
#         end

#         lifecycle.after(:perform) do |worker, job|
#           job.tomqueue_work && job.tomqueue_work.ack!
#         end
#       end
#     end
#       # This is a reference to the TomQueue::Work object that triggered
#       # this job
#       attr_accessor :tomqueue_work

#       after_commit :tomqueue_publish, :on => :create


#       # Publish an AMQP message to trigger the job
#       def tomqueue_publish
#         self.class.tomqueue_manager.publish(JSON.dump({"delayed_job_id" => self.id}), {
#           :run_at => self.run_at,
#           :priority => self.class.tomqueue_priority_map.fetch(self.priority, TomQueue::NORMAL_PRIORITY)
#         })
#       end

#       # Returns a shared instance of the QueueManager
#       def self.tomqueue_manager
#         @@tomqueue_manager ||= TomQueue::QueueManager.new
#       end

#       # This is called when a worker wants to reserve a single job
#       # We pop a message off the AMQP queue; look up and return the
#       # Delayed::Job instance from the database. And DJ is none the
#       # wiser.
#       def self.reserve(worker, max_run_time = ::Delayed::Worker.max_run_time)

#         # Make sure we can stop a worker that is blocked on a pop
#         Delayed::Worker.raise_signal_exceptions = true
#         work = self.tomqueue_manager.pop
#         Delayed::Worker.raise_signal_exceptions = false

#         # Load up the job
#         job = self.ready_to_run(worker.name, max_run_time).find_by_id(JSON.load(work.payload)['delayed_job_id'], :lock => true)
#         if job
#           job.update_attributes!({:locked_at => db_time_now, :locked_by => worker.name}, { :without_protection => true })
#           job.tomqueue_work = work
#         else
#           work.ack!
#         end

#         job
#       rescue
#         puts "FAILED TO RESERVE JOB: #{$!.inspect}"
#         work && work.ack!
#       end
#     end

    
#   end
# end