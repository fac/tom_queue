require "benchmark"

module TomQueue
  module Layers
    class Log < TomQueue::Stack::Layer
      def call(work, options)
        puts "Enqueuing #{work}"
        execution_time = Benchmark.realtime do
          chain.call(work, options)
        end
        puts "Completed in %.4fs" % execution_time
      end
    end
  end
end
