module TomQueue

  module LoggingHelper
    def self.included(base)
      base.extend(TomQueue::LoggingHelper)
    end

    [:debug, :info, :warn, :error].each do |level|
      define_method(level) do |message|

        if TomQueue.logger && TomQueue.logger.send(:"#{level}?")
          message ||= yield if block_given?
          TomQueue.logger.send(level, message) if message
        end
      end
    end

         
  end

end