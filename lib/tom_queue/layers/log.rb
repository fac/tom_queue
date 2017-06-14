module TomQueue
  module Layers
    class Log < TomQueue::Stack::Layer
      def initialize(*args)
        # @logger = TomQueue.logger
        super
      end

      def call(work, options)
        puts "Log"
        @chain.call(work, options)
      end
    end
  end
end
