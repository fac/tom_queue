module TomQueue
  class Error < StandardError
    attr_reader :job, :work, :options

    def initialize(message, additional = {})
      super(message)
      @job = additional[:job]
      @work = additional[:work]
      @options = additional[:options] || {}
    end
  end

  # Exception class to trap errors which can nack the message
  class RetryableError < TomQueue::Error; end

  # Exception class to trap errors which should ack and republish the message
  class RepublishableError < TomQueue::Error; end

  # Exception class to trap errors which should ack and drop the message
  class PermanentError < TomQueue::Error; end

  class DeserializationError < TomQueue::PermanentError; end

  module DelayedJob
    class NotFoundError < TomQueue::PermanentError; end
    class DigestMismatchError < TomQueue::PermanentError; end
    class EarlyNotificationError < TomQueue::RetryableError; end
    class LockedError < TomQueue::RetryableError; end
    class FailedError < TomQueue::PermanentError; end
  end
end
