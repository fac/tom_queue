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

end

class VerboseMutex < Mutex
  def initialize
    @lockers = {}
  end
  def lock
    @lockers[Thread.current] = caller
    super
  rescue
    puts "EXCEPTION: #{$!.inspect}"
    @lockers.each_pair do |thread, caller|
      puts "Thread #{thread}:"
      puts caller.join("\n\t")
    end
  end
  def unlock
    super
  ensure
    @lockers.delete(Thread.current)
  end

end
class Bunny::Transport
  alias_method :old_initialize, :initialize
  def initialize(*args)
    old_initialize(*args)
   # @writes_mutex = VerboseMutex.new
  end
end