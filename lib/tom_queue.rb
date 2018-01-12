# This is a bit of a library-in-a-library, for the time being
# 
# This module manages the interaction with AMQP, handling publishing of
# work messages, scheduling of work off the AMQP queue, etc.
#
##
#
# You probably want to start with TomQueue::QueueManager
#
module TomQueue

  # Public: Priority values for QueueManager#publish
  #
  # Rather than an arbitrary numeric scale, we use distinct
  # priority values, one should be selected depending on the
  # type and use-case of the work.
  #
  # The scheduler simply trumps lower-priority jobs with higher
  # priority jobs. So ensure you don't saturate the worker with many
  # or lengthy high priority jobs as you'll negatively impact normal
  # and bulk jobs.
  #
  # HIGH_PRIORITY - use where the job is relatively short and the
  #    user is waiting on completion. For example sending a password
  #    reset email.
  #
  # NORMAL_PRIORITY - use for longer-interactive tasks (rebuilding ledgers?)
  #
  # BULK_PRIORITY - typically when you want to schedule lots of work to be done
  #   at some point in the future - background emailing, cron-triggered
  #   syncs, etc.
  #
  HIGH_PRIORITY = "high"
  NORMAL_PRIORITY = "normal"
  LOW_PRIORITY = "low"
  BULK_PRIORITY = "bulk"
  
  require 'tom_queue/logging_helper'
  
  require 'tom_queue/queue_manager'
  require 'tom_queue/work'
  
  require 'tom_queue/deferred_work_set'
  require 'tom_queue/deferred_work_manager'

  require 'tom_queue/external_consumer'

  require 'tom_queue/sorted_array'

  # Public: Sets the bunny instance to use for new QueueManager objects
  def bunny=(new_bunny)
    @@bunny = new_bunny
  end
  # Public: Returns the current bunny instance
  #
  # Returns whatever was passed to TomQueue.bunny = 
  def bunny
    defined?(@@bunny) && @@bunny
  end
  module_function :bunny, :bunny=

  def default_prefix=(new_default_prefix)
    @@default_prefix = new_default_prefix
  end
  def default_prefix
    defined?(@@default_prefix) && @@default_prefix
  end
  module_function :default_prefix=, :default_prefix


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