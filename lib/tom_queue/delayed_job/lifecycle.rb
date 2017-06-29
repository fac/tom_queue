module TomQueue
  module DelayedJob
    class Lifecycle
      include LoggingHelper
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
        if EVENTS.include?(event)
          if job.payload_object.respond_to?(event)
            debug "[#{job.class.name}##{job.id}] Invoking lifecycle hook #{event}"
            job.payload_object.send(event, *[job, args].flatten)
          else
            debug "[#{job.class.name}##{job.id}] No lifecycle hook #{event}, skipping"
          end
        end
      end
    end
  end
end
