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
        self.find_each { |instance| instance.tomqueue_publish }
      end

      # Private: Skip the implicit tomqueue_publish when a record is being saved
      attr_accessor :skip_publish

      # This triggers the publish whenever a record is saved (and committed to
      # stable storage).
      #
      # It's also worth noting that after_commit masks exceptions, so a failed
      # publish won't bring down the caller.
      #
      after_commit :tomqueue_publish, :if => lambda { persisted? && !!run_at && !failed_at }

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

        if locked_at && locked_by
          custom_run_at = self.locked_at + Delayed::Worker.max_run_time
        end

        self.class.tomqueue_manager.publish(tomqueue_payload, {
          :run_at   => custom_run_at || self.run_at,
          :priority => self.class.tomqueue_priority_map.fetch(self.priority, TomQueue::NORMAL_PRIORITY)
        })
      rescue Exception => e
        r = TomQueue.exception_reporter
        r && r.notify(e)
        
        #TODO: Write error to the log!!
        
        raise
      end

      # Private: Prepare an AMQP payload for this job
      #
      # This is used by both #tomqueue_publish as well as tests to avoid
      # maintaining mock payloads all over the place.
      #
      # Returns a string
      def tomqueue_payload
        JSON.dump({
          "delayed_job_id"         => self.id,
          "delayed_job_digest"     => tomqueue_digest,
          "delayed_job_updated_at" => self.updated_at.iso8601(0)
        })
      end

      # Private: Calculate a hexdigest of the attributes
      #
      # This is used to detect if the received message is stale, as it's sent as part of the
      # AMQP payload and then re-calculated when the worker is about to run the job.
      #
      # Returns a string
      BROKEN_DIGEST_CLASSES = [DateTime, Time, ActiveSupport::TimeWithZone]
      def tomqueue_digest
        digest_string = self.attributes.map { |k,v| BROKEN_DIGEST_CLASSES.include?(v.class) ? [k,v.to_i] : [k,v.to_s] }.to_s
        Digest::MD5.hexdigest(digest_string)
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

        # Grab a job from the QueueManager - will block here, ensure we can be interrupted!
        Delayed::Worker.raise_signal_exceptions, old_value = true, Delayed::Worker.raise_signal_exceptions
        work = self.tomqueue_manager.pop
        Delayed::Worker.raise_signal_exceptions = old_value

        # We have to be careful here, we grab the DJ lock inside a transaction that holds
        # a write lock on the record to avoid potential race conditions with other workers
        # doing the same...
        job = Delayed::Job.transaction do
          decoded_payload = JSON.load(work.payload)

          # Load the job, ensuring we have a write lock so other workers in the same position
          # block whilst we grab a lock
          job = Delayed::Job.find_by_id(decoded_payload['delayed_job_id'], :lock => true)

          # Has the job changed since the message was published?
          if decoded_payload['delayed_job_digest'] && job.tomqueue_digest != decoded_payload['delayed_job_digest']
            job = nil

          # is the job locked by someone else?
          elsif job.locked_by && job.locked_at && job.locked_at > (self.db_time_now - max_run_time)
            job = nil

          end

          if job
            # Now lock it!
            job.locked_by = worker.name
            job.locked_at = self.db_time_now
            job.save!

            # This is a cleanup job, just in case the worker crashes whilst running the job
            # or anything, in fact, whilst the DJ lock is held!
            #job.tomqueue_publish(self.db_time_now + max_run_time)
          end

          job
        end

        # OK! We made it here, how exciting. Ack the message so it doesn't get re-delivered
        work.ack!

        job
      end

    end
  end
end
