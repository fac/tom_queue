module TomQueue
  module DelayedJob

    require 'tom_queue/delayed_job/ack_work_plugin'
    require 'tom_queue/delayed_job/external_messages'
    require 'tom_queue/delayed_job/job'

    # Public: This installs the dynamic patches into Delayed Job to move scheduling over
    # to AMQP. Generally, this should be called during a Rails initializer at some point.
    def apply_hook!
      unless TomQueue.config[:override_worker]
        Delayed::Worker.sleep_delay = 0
        Delayed::Worker.backend = TomQueue::DelayedJob::Job
      end

      if TomQueue.config[:override_enqueue]
        Delayed::Job.send(:extend, TomQueue::DelayedJob::ClassMethods)
      end
    end
    module_function :apply_hook!
  end
end
