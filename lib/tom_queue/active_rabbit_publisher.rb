module TomQueue
  # Replaces QueueManager in TomQueue::DelayedJob::Job.queue_manager when you only want to publish.
  #
  # Leans on ActiveRabbit for publishing duties.
  #
  class ActiveRabbitPublisher
    attr_accessor :handler

    def initialize(handler:)
      self.handler = handler
    end

    # Grabs the queue prefix from the manager
    def prefix
      TomQueue::DelayedJob::Job.tomqueue_manager.prefix
    end

    def publish(payload, opts = {})
      priority = opts.fetch('priority', opts.fetch(:priority, TomQueue::NORMAL_PRIORITY))
      run_at = opts.fetch('run_at', opts.fetch(:run_at) { Time.now })

      if run_at > Time.now
        # TODO: implement
        fail "can't schedule future jobs yet"

      else
        # We're only pushing messages up, don't create the exchange if it doesn't exist
        # Mirrors how QueueManager behaves for publishing
        exchange = handler.exchange(:topic, "#{prefix}.work", passive: true)

        exchange.publish(
          payload,
          key: priority,
          headers: {
            job_priority: priority,
            run_at: run_at.iso8601(4)
          }
        )
      end

      nil
    end

  end
end
