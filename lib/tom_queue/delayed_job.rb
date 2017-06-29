module TomQueue
  module DelayedJob

    require 'tom_queue/delayed_job/ack_work_plugin'
    require 'tom_queue/delayed_job/external_messages'
    require 'tom_queue/delayed_job/job'

    # Map External priority values to the TomQueue priority levels
    def priority_map
      @@priority_map ||= Hash.new(TomQueue::NORMAL_PRIORITY)
    end
    module_function :priority_map

    # Public: This installs the dynamic patches into Delayed Job to move scheduling over
    # to AMQP. Generally, this should be called during a Rails initializer at some point.
    def apply_hook!
      Delayed::Worker.sleep_delay = 0
      Delayed::Worker.backend = TomQueue::DelayedJob::Job

      if TomQueue.config[:override_enqueue]
        Delayed::Job.send(:extend, TomQueue::DelayedJob::ClassMethods)
      end
    end
    module_function :apply_hook!

    # Public: External Message handlers
    #
    def handlers=(new_handlers)
      @@handlers = new_handlers
    end
    def handlers
      @@handlers ||= []
    end
    module_function :handlers, :handlers=

  end
end
