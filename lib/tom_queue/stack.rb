module TomQueue
  class Stack
    TERMINATOR = lambda { |work, options| [work, options] }

    # Public: Insert a middleware layer at the beginning of the stack.
    # middleware - a descendant of TomQueue::Stack::Layer
    # options - a hash of options to use when instantiating the middleware
    #
    # Returns nothing
    def self.insert(middleware, options = {})
      @stack = middleware.new(stack, options)
    end

    # Public: Append a middleware layer to the end of the stack.
    # middleware - a descendant of TomQueue::Stack::Layer
    # options - a hash of options to use when instantiating the middleware
    #
    # Returns nothing
    def self.use(middleware, options = {})
      if stack
        stack.append(middleware, options)
      else
        @stack = middleware.new(nil, options)
      end
    end

    # Public: Entry point to call the stack
    # work - the object being worked on (Job class instance usually)
    # options - Hash of options defining how the job should be run
    #
    # Returns modified [work, options]
    def self.call(work, options)
      (stack || TERMINATOR).call(work, options)
    end

    # Internal: The class' middleware stack
    #
    # Returns a TomQueue::Stack::Layer instance or nil
    def self.stack
      @stack ||= nil
    end

    class Layer
      attr_accessor :config

      def initialize(chain = nil, config = {})
        @chain = chain
        @config = config
      end

      # Public: Execute the middleware layer.
      # Subclasses should _usually_ chain.call(work, options) unless they want to
      # stop execution of the stack in which case they should just return
      #
      # work - the object being worked on (Job class instance usually)
      # options - Hash of options defining how the job should be run
      #
      # Returns modified [work, options]
      def call(work, options)
        return [work, options]
      end

      # Public: Replaces the terminator with a new middleware, or passes it
      # to the next layer in the chain
      # middleware - a descendant of TomQueue::Stack::Layer
      # options - a hash of options to use when instantiating the middleware
      #
      # Returns nothing
      def append(middleware, options = {})
        if @chain.nil?
          @chain = middleware.new(nil, options)
        else
          @chain.append(middleware, options)
        end
      end

      # Internal: Return the next layer in the stack. If we're at the bottom layer
      # return the TERMINATOR reflector to begin the journey back up the layers
      #
      # Returns a Layer or Proc instance
      def chain
        @chain || TomQueue::Stack::TERMINATOR
      end
    end
  end
end
