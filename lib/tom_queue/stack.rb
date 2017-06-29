module TomQueue
  class Stack
    TERMINATOR = lambda { |*a| a }

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
    #
    def self.call(*args)
      (stack || TERMINATOR).call(*args)
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
      def call(*args)
        return args
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
        @chain || Stack::TERMINATOR
      end
    end
  end
end
