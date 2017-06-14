require "active_support/core_ext/array/extract_options"

module TomQueue
  module Job
    class Preparer
      attr_reader :options, :args

      def initialize(*args)
        @options = args.extract_options!.dup
        @args = args
      end

      def prepare
        [work, prepare_options]
      end

      private

      def work
        options[:payload_object] || args.shift
      end

      def prepare_options
        {
          run_at: Time.now,
          priority: 0
        }.merge(options)
      end
    end
  end
end
