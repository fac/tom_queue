# All files in delayed_job_shims are taken directly from
# the delayed_job gem and namespaced to TomQueue. The intention
# is that these will be stripped back to provide only the required
# functionality, so for now we keep them in one place.

require "tom_queue/delayed_job_shims/serialization"
require "tom_queue/delayed_job_shims/compatibility"
require "tom_queue/delayed_job_shims/message_sending"
require "tom_queue/delayed_job_shims/performable_method"
require "tom_queue/delayed_job_shims/performable_mailer"

module TomQueue
  module DelayedJob
    def self.apply_hook!
      # noop
    end

    Job = Persistence::Model
  end
end

Object.send(:include, TomQueue::MessageSending)
Module.send(:include, TomQueue::MessageSending::ClassMethods)
