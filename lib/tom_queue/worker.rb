require "delayed_job"

module TomQueue
  class Worker < ::Delayed::Worker
  end
end
