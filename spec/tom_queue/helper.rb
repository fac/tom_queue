require 'tom_queue/base_helper'

RSpec.configure do |r|

  r.before do
    TomQueue.logger ||= Logger.new("/dev/null")
    TomQueue.default_prefix = "test-#{Time.now.to_f}"
    TomQueue::DelayedJob.apply_hook!
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
  end

end
