# This is a bit of a library-in-a-library, for the time being
#
# This module manages the interaction with AMQP, handling publishing of
# work messages, scheduling of work off the AMQP queue, etc.
#
##
#
# You probably want to start with TomQueue::QueueManager
#

require 'delayed_job'
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/delayed")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/delayed_job.rb")
loader.ignore("#{__dir__}/delayed_job_active_record.rb")
loader.setup

require "active_support"

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
  end
end
