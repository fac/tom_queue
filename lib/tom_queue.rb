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

  require 'tom_queue/queue_manager'
  require 'tom_queue/work'
  
  require 'tom_queue/deferred_work_set'
  require 'tom_queue/deferred_work_manager'

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
  end


  # Public: This installs the dynamic patches into Delayed Job to move scheduling over
  # to AMQP. Generally, this should be called during a Rails initializer at some point.
  def self.hook_delayed_job!
    require 'tom_queue/delayed_job_hook'
    
    Delayed::Worker.sleep_delay = 0
    Delayed::Worker.backend = TomQueue::DelayedJobHook::Job
    #Delayed::Worker.plugins << TomQueue::DelayedJobHook::AmqpConsumer
  end

end