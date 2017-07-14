module TomQueue
  class Error < StandardError
    attr_reader :job, :work, :options

    def initialize(message, additional = {})
      super(message)
      @job = additional.delete(:job)
      @work = additional.delete(:work)
      @options = additional
    end
  end

  class WorkerTimeout < Timeout::Error
    def message
      seconds = TomQueue::Worker.max_run_time.to_i
      "#{super} (TomQueue::Worker.max_run_time is only #{seconds} second#{seconds == 1 ? '' : 's'})"
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
    class EarlyNotificationError < TomQueue::RepublishableError; end
    class LockedError < TomQueue::RepublishableError; end
    class FailedError < TomQueue::PermanentError; end
  end
end
