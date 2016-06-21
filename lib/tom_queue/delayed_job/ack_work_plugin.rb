require 'active_support/concern'

module TomQueue
  module DelayedJob
    class AckWorkPlugin < Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.after(:perform) do |_, job|
          job.tomqueue_work.ack! if job.tomqueue_work
        end
      end

      Delayed::Worker.plugins << self
    end
  end
end
