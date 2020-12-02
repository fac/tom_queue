module TomQueue
  module DelayedJob

    require 'tom_queue/delayed_job/ack_work_plugin'
    require 'tom_queue/delayed_job/job'

    # Map External priority values to the TomQueue priority levels
    def priority_map
      @@priority_map ||= Hash.new(TomQueue::NORMAL_PRIORITY)
    end
    module_function :priority_map

    # Public: This installs the dynamic patches into Delayed Job to move scheduling over
    # to AMQP. Generally, this should be called during a Rails initializer at some point.
    def apply_hook!
      Delayed::Worker.backend = TomQueue::DelayedJob::Job
      old_sleep_delay, Delayed::Worker.sleep_delay = Delayed::Worker.sleep_delay, 0
      yield if block_given?
    ensure
      if block_given?
        Delayed::Worker.backend = :active_record
        Delayed::Worker.sleep_delay = old_sleep_delay
      end
    end
    module_function :apply_hook!
  end
end
