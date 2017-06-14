require "tom_queue/job/preparer"
require "tom_queue/layers/log"
require "tom_queue/layers/persist"
require "tom_queue/layers/publish"

module TomQueue
  class Enqueue < TomQueue::Stack
    use Layers::Log
    use Layers::Persist
    use Layers::Publish
  end

  # Public: Intended to be a direct replacement for Delayed::Job.enqueue, this
  # takes the arguments, separates them into work and queue options, and passes them
  # into the enqueue call stack
  #
  # Returns [work, options]
  def enqueue(*args)
    work, options = Job::Preparer.new(*args).prepare
    Enqueue.call(work, options)
  end

  module_function :enqueue
end
