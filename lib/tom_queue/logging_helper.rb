module TomQueue

  module LoggingHelper
    def self.included(base)
      base.extend(TomQueue::LoggingHelper)
    end

    [:debug, :info, :warn, :error].each do |level|
      eval <<-RUBY
        def #{level}(message=nil, &block)
          if TomQueue.logger && TomQueue.logger.#{level}?
            message ||= yield if block_given?
            TomQueue.logger.#{level}(message)
          end
        end
      RUBY
    end
  end
end