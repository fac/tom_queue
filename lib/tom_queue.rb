# frozen_string_literal: true
# 
# TomQueue is a Background Job processing library, evolved from DelayedJob.
#
# It persists work as records in a database table, emulating the behaviour of Delayed Job
# but schedules job across worker processes using AMQP notifications and coordinates work
# into shards using ZooKeeper.
#
##

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/delayed")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/delayed_job.rb")
loader.ignore("#{__dir__}/delayed_job_active_record.rb")
loader.ignore("#{__dir__}/tom_queue/tasks.rb")
loader.ignore("#{__dir__}/tom_queue/datadog_integration.rb")
loader.setup

require "active_support"
require "tom_queue/railtie"

module TomQueue

  require "tom_queue/logging_helper"

  require "tom_queue/publisher"
  require "tom_queue/queue_manager"
  require "tom_queue/work"

  require "tom_queue/deferred_work_set"
  require "tom_queue/deferred_work_manager"

  require "tom_queue/sorted_array"

  mattr_accessor :bunny, :publisher, :default_prefix, :job_limit

  self.publisher = Publisher.new

  # Public: Set an object to receive notifications if an internal exception
  # is caught and handled.
  #
  # IT should be an object that responds to #notify(exception) and should be
  # thread safe as reported exceptions will be from background threads crashing.
  #
  class << self
    attr_accessor :exception_reporter
    attr_accessor :logger

    def in_worker?
      /tomqueue/.match? $PROGRAM_NAME
    end
  end
end
