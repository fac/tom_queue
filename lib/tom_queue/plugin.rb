require 'active_support/core_ext/class/attribute'

module TomQueue
  class Plugin
    class_attribute :callback_block

    def self.callbacks(&block)
      self.callback_block = block
    end

    def initialize(lifecycle)
      self.class.callback_block.call(lifecycle) if self.class.callback_block
    end
  end
end
