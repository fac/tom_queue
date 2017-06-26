module TomQueue
  module DelayedJob
    class Lifecycle
      EVENTS = [
        :before,
        :success,
        :error,
        :after,
        :failure
      ]

      attr_reader :job

      def initialize(job)
        @job = job
      end

      def hook(event, *args)
        if EVENTS.include?(event) && job.payload_object.respond_to?(event)
          job.send(event, *args)
        end
      end
    end
  end
end
