require "benchmark"

module TomQueue
  module Layers
    class Log < TomQueue::Stack::Layer
      def call(work, options)
        chain.call(work, options.merge(logger: logger))
      end

      private

      def logger
        @logger ||= (TomQueue.logger || Logger.new(STDOUT))
      end
    end
  end
end
