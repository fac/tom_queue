module TomQueue
  module DelayedJob
    module ClassMethods
      def enqueue(*args)
        # TODO: Hook in here and don't call DJ's enqueue method
        super
      end
    end
  end
end

if defined?(Delayed) && defined?(Delayed::Job)
  Delayed::Job.send(:extend, TomQueue::DelayedJob::ClassMethods)
end
