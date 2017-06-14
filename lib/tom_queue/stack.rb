module TomQueue
  class Stack
    def self.insert(middleware, options = {})
      @@stack = middleware.new(stack, options)
    end

    def self.stack
      @@stack ||= Terminator.new(nil, nil)
    end

    class Layer
      def initialize(chain, options = {})
        @chain = chain
        @options = options
      end

      def call(job)
        raise NotImplementedError, "TomQueue Stack Layers must implement their own call method"
      end
    end

    class Terminator < Layer
      def call(*args)
        return *args
      end
    end
  end
end
