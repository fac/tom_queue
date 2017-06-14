require "tom_queue/job/preparer"
require "tom_queue/layers/log"
require "tom_queue/layers/persist"
require "tom_queue/layers/publish"

module TomQueue
  class Enqueue < TomQueue::Stack
    insert Layers::Publish
    insert Layers::Persist
    insert Layers::Log
  end

  def enqueue(*args)
    work, options = Job::Preparer.new(*args).prepare
    Enqueue.stack.call(work, options)
  end

  module_function :enqueue
end

binding.pry; ""
