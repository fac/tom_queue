require "tom_queue/job/preparer"
require "tom_queue/layers/log"
require "tom_queue/layers/persist"
require "tom_queue/layers/publish"

module TomQueue
  class Enqueue < TomQueue::Stack
    use Layers::Persist
    use Layers::Publish
  end

  # Public: Push a work unit into the queue stack
  #
  # work - the work unit being enqueued
  # options - Hash of options defining how the job should be run
  #
  # Returns [work, options]
  def enqueue(work, options = {})
    Enqueue.call(work, options)
  end

  module_function :enqueue
end
