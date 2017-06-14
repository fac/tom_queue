module TomQueue
  module Job
    class Preparer
      # Mostly taken from https://github.com/collectiveidea/delayed_job/blob/master/lib/delayed/backend/job_preparer.rb

      # TODO: Allow these to be set from TomQueue.config
      DEFAULT_QUEUE_NAME = "normal"
      DEFAULT_PRIORITY = 0

      attr_reader :options, :args

      def initialize(*args)
        @options = args.extract_options!.dup
        @args = args
      end

      def prepare
        set_payload
        set_queue_name
        set_priority
        handle_deprecation
        options
      end

    private

      def set_payload
        options[:payload_object] ||= args.shift
      end

      def set_queue_name
        if options[:queue].nil? && options[:payload_object].respond_to?(:queue_name)
          options[:queue] = options[:payload_object].queue_name
        else
          options[:queue] ||= DEFAULT_QUEUE_NAME
        end
      end

      def set_priority
        options[:priority] ||= DEFAULT_PRIORITY
      end

      def handle_deprecation
        if args.size > 0
          warn '[DEPRECATION] Passing multiple arguments to `#enqueue` is deprecated. Pass a hash with :priority and :run_at.'
          options[:priority] = args.first || options[:priority]
          options[:run_at]   = args[1]
        end

        unless options[:payload_object].respond_to?(:perform)
          raise ArgumentError, 'Cannot enqueue items which do not respond to perform'
        end
      end
    end
  end
end
