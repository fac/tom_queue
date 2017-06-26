module TomQueue
  module DelayedJob
    class Error < StandardError
      attr_reader :job

      def initialize(message, job = nil)
        super(message)
        @job = job
      end
    end

    class RetryableError < TomQueue::DelayedJob::Error; end
    class PermanentError < TomQueue::DelayedJob::Error; end

    class NotFoundError < PermanentError; end
    class DigestMismatchError < PermanentError; end
    class EarlyNotificationError < RetryableError; end
    class LockedError < RetryableError; end
    class FailedError < PermanentError; end
    class DeserializationError < PermanentError; end
  end
end
