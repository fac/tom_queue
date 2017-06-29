module TomQueue
  class Stack
    TERMINATOR = lambda { |work, options| [work, options] }

    # Public: Insert a layer at the beginning of the stack.
    # layer - a descendant of TomQueue::Stack::Layer
    # options - a hash of options to use when instantiating the layer
    #
    # Returns nothing
    def self.insert(layer, options = {})
      @stack = layer.new(stack, options)
    end

    # Public: Append a layer to the end of the stack.
    # layer - a descendant of TomQueue::Stack::Layer
    # options - a hash of options to use when instantiating the layer
    #
    # Returns nothing
    def self.use(layer, options = {})
      if stack
        stack.append(layer, options)
      else
        @stack = layer.new(nil, options)
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

    # Internal: The class' layer stack
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

      # Public: Execute the stack
      # Subclasses should _usually_ chain.call(work, options) unless they want to
      # stop execution of the stack in which case they should just return
      #
      # work - the object being worked on (Job class instance usually)
      # options - Hash of options defining how the job should be run
      #
      # Returns modified [work, options]
      def call(work, options)
        [work, options]
      end

      # Public: Adds a new layer if this layer is at the bottom of the stack,
      # or passes it to the next layer in the chain
      #
      # layer - a descendant of TomQueue::Stack::Layer
      # options - a hash of options to use when instantiating the layer
      #
      # Returns nothing
      def append(layer, options = {})
        if @chain.nil?
          @chain = layer.new(nil, options)
        else
          @chain.append(layer, options)
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
