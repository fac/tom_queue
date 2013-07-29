module TomQueue
  module DelayedJob

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
    end
    module_function :apply_hook!

  end

  require 'tom_queue/delayed_job/job'

end
