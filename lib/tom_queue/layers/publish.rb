module TomQueue
  module Layers
    class Publish < TomQueue::Stack::Layer
      def call(work, options)
        puts "Publish"
        @chain.call(work, options)
      end
    end
  end
end
