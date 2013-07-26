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
    # two pieces of information, the job ID, so the job can be located and a 
    # digest of the record attributes so stale notifications can be detected.
    #
    # This means that the worker can simply load a job and, if a record is
    # found, quickly drop the notification if any of the attributes have been
    # changed since the message was published. Another notification will 
    # likely be en-route.
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
    #   - rather than leaving the job un-acked for the duration of the process,
    #     we load the job, lock it and then re-publish a message that will
    #     trigger a worker after the maximum run duration. This will likely
    #     just be dropped since the job will have run successfully and been
    #     deleted, but equally could catch a job that has crashed the worker.
    #     This ties into the behaviour of DJ more closely than leaving the job
    #     un-acked.
    #
    # During the worker reserve method, we do a number of things:
    #
    #  - look up the job by ID. We do this with an explicit pessimistic write
    #    lock for update, so concurrent workers block.
    #
    #  - if there is no record, we ack the AMQP message and do nothing.
    #
    #  - if there is a record, we lock the job with our worker and save it.
    #    (releasing the lock) At this point, concurrent workers won't find 
    #    the job as it has been DJ locked by this worker.
    #
    #  - when the job completes, we ack the message from the broker, and we're
    #    done.
    #
    #  - in the event we get a message and the job is locked, the most likely 
    #    reason is the other worker has crashed and the broker has re-delivered.
    #    Since the job will have been updated (to lock it) the digest won't match
    #    so we schedule a message to pick up the job when the max_run_time is 
    #    reached.
    #
    class Job < ::Delayed::Backend::ActiveRecord::Job

      include TomQueue::LoggingHelper

      # Public: This provides a shared queue manager object, instantiated on
      # the first call
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
      after_save   :tomqueue_trigger,          :if => lambda { persisted? && !!run_at && !failed_at && !skip_publish}
      
      after_commit :tomqueue_publish_triggers, :unless => lambda { self.class.tomqueue_triggers.empty? }
      after_rollback :tomqueue_clear_triggers, :unless => lambda { self.class.tomqueue_triggers.empty? }

      @@tomqueue_triggers = []
      cattr_reader :tomqueue_triggers

      def tomqueue_publish_triggers
        while job = self.class.tomqueue_triggers.pop
          job.tomqueue_publish
        end
      end
      def tomqueue_clear_triggers
        self.class.tomqueue_triggers.clear
      end
      def tomqueue_trigger
        self.class.tomqueue_triggers << self
      end

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
        return nil if self.skip_publish
        raise ArgumentError, "cannot publish an unsaved Delayed::Job object" if new_record?

        debug "[tomqueue_publish] Pushing notification for #{self.id} to run in #{((custom_run_at || self.run_at) - Time.now).round(2)}"
        
        tq_priority = self.class.tomqueue_priority_map.fetch(self.priority, nil)
        if tq_priority.nil?
          tq_priority = TomQueue::NORMAL_PRIORITY
          warn "[tomqueue_publish] Unknown priority level #{self.priority} specified, mapping to NORMAL priority"
        end

        self.class.tomqueue_manager.publish(tomqueue_payload, {
          :run_at   => custom_run_at || self.run_at,
          :priority => tq_priority
        })

      rescue Exception => e
        r = TomQueue.exception_reporter
        r && r.notify(e)

        error "[tomqueue_publish] Exception during publish: #{e.inspect}"
        e.backtrace.each { |l| info l }
        
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
      # This is used to detect if the received message is stale, as it's
      # sent as part of the AMQP payload and then re-calculated when the
      # worker is about to run the job.
      #
      # Returns a string
      BROKEN_DIGEST_CLASSES = [DateTime, Time, ActiveSupport::TimeWithZone]
      def tomqueue_digest
        digest_string = self.attributes.map { |k,v| BROKEN_DIGEST_CLASSES.include?(v.class) ? [k,v.to_i] : [k,v.to_s] }.to_s
        Digest::MD5.hexdigest(digest_string)
      end


      # Public: is this job locked
      #
      # Returns boolean true if the job has been locked by a worker
      def locked?
        !!locked_by && !!locked_at && (locked_at + Delayed::Worker.max_run_time) >= Delayed::Job.db_time_now
      end

      # Public: Retrieves a job with a specific ID, acquiring a lock
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
      # Returns * a Delayed::Job instance if the job was found and lock acquired
      #         * nil if the job wasn't found
      #         * false if the job was found, but the lock wasn't acquired.
      def self.acquire_locked_job(job_id, worker)

        # We have to be careful here, we grab the DJ lock inside a transaction that holds
        # a write lock on the record to avoid potential race conditions with other workers
        # doing the same...
        Delayed::Job.transaction do

          # Load the job, ensuring we have a write lock so other workers in the same position
          # block, avoiding race conditions
          job = Delayed::Job.find_by_id(job_id, :lock => true)

          if job.nil?
            job = nil
          
          elsif job.locked?
            job = false
          
          elsif job.locked_at || job.locked_by || (!block_given? || yield(job) == true)
              job.skip_publish = true
              
              job.locked_by = worker.name
              job.locked_at = self.db_time_now
              job.save!

              job.skip_publish = nil
          else
            job = nil
          end

          job

        end
      end





#           # Has the job changed since the message was published?
#          elsif digest && job.tomqueue_digest != digest
# # #            debug "[acquire_locked_job] Digest mismatch, discarding message."
# #
# #            nil

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

        if work.nil?
          warn "[reserve] TomQueue#pop returned nil, stalling for a second."
          sleep 1.0

          nil
        else

          decoded_payload = JSON.load(work.payload)
          job_id = decoded_payload['delayed_job_id']
          digest = decoded_payload['delayed_job_digest']

          debug "[reserve] Popped notification for #{job_id}"
          locked_job = self.acquire_locked_job(job_id, worker)

          if locked_job
            info "[reserve] Acquired DB lock for job #{job_id}"

            locked_job.tomqueue_work = work
          else
            work.ack!

            if locked_job == false
              # In this situation, we re-publish a message to run in max_run_time
              # since the likely scenario is a woker has crashed and the original message
              # was re-delivered.
              #
              # We schedule another AMQP message to arrive when the job's lock will have expired.
              Delayed::Job.find_by_id(job_id).tap do |job|
                debug "[reserve] Notified about locked job #{job.id}, will schedule follow up at #{job.locked_at + max_run_time + 1}"
                job && job.tomqueue_publish(job.locked_at + max_run_time + 1)
              end

              locked_job = nil
            end
          end

          locked_job
        end

      rescue JSON::ParserError => e
        work.ack!

        TomQueue.exception_reporter && TomQueue.exception_reporter.report(e)
        error "[reserve] Failed to parse JSON payload: #{e.message}. Dropping AMQP message."

        nil
      end

      # Internal: This is the AMQP notification object that triggered this job run
      # and is used to ack! the work once the job has been invoked
      #
      # Returns nil or TomQueue::Work object
      attr_accessor :tomqueue_work

      # Internal: This wraps the job invocation with an acknowledgement of the original
      # TomQueue work object, if one is around.
      #
      def invoke_job
        super
      ensure
        debug "[invoke job:#{self.id}] Invoke completed, acking message."
        self.tomqueue_work && self.tomqueue_work.ack!
      end

    end
  end
end
