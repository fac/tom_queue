require "tom_queue/job/preparer"
require "tom_queue/enqueue/delayed_job"
require "tom_queue/enqueue/publish"

module TomQueue
  module Enqueue
    class Stack < TomQueue::Stack
      use DelayedJob
      use Publish
    end
  end

  # Public: Push a work unit into the queue stack
  #
  # work - the work unit being enqueued
  # options - Hash of options defining how the job should be run
  #
  # Returns [work, options]
  def enqueue(work, options = {})
    Enqueue::Stack.call(work, options)
  end

  module_function :enqueue
end
