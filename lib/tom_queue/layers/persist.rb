module TomQueue
  module Layers
    class Persist < TomQueue::Stack::Layer
      def call(work, options)
        puts "Persist"
        chain.call(work, options)
      end
    end
  end
end
