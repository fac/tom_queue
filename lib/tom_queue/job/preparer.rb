require "active_support/core_ext/array/extract_options"

module TomQueue
  class Job
    class Preparer
      DEFAULT_PRIORITY = 0
      attr_reader :options, :args

      def initialize(*args)
        @options = args.extract_options!.dup
        @args = args
      end

      def prepare
        work = options.delete(:payload_object) || args.shift

        options[:priority] ||= DEFAULT_PRIORITY

        if options[:queue].nil?
          if options[:payload_object].respond_to?(:queue_name)
            options[:queue] = options[:payload_object].queue_name
          end
          options[:queue] ||= TomQueue::Worker.default_queue_name
        end

        if args.size > 0
          TomQueue.logger.warn "[DEPRECATION] Passing multiple arguments to `#enqueue` is deprecated. Pass a hash with :priority and :run_at."
          options[:priority] = args.first || options[:priority]
          options[:run_at]   = args[1]
        end

        unless work.respond_to?(:perform)
          raise ArgumentError, "Cannot enqueue items which do not respond to perform"
        end

        [work, options]
      end
    end
  end
end
