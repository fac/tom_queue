MAX_TIMEOUT = 5
TIMESTAMP_REGEX = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+/
A_MOMENT = (0.1).seconds

# Retrieve a number of messages from the worker
# count - the number of messages to wait for
# seconds - the maximum number of seconds to wait
#
# Returns [String, ...]
def worker_messages(count, seconds = MAX_TIMEOUT)
  messages = []
  begin
    Timeout.timeout(seconds) do
      while messages.length < count
        messages << TomQueue.test_logger.readline
      end
    end
  rescue Timeout::Error
  end
  messages
end

# Wait a given number of seconds for a message to arrive
# message - a string to match on
# seconds - the maximum number of seconds to wait
#
# Returns boolean
def message(message, seconds = MAX_TIMEOUT)
  received = false
  Timeout.timeout(seconds) do
    while !received do
      output = TomQueue.test_logger.readline
      received = !!(output =~ /#{Regexp.escape(message)}/)
    end
  end
  true
rescue Timeout::Error
  false
end

# Extract timestamps from an array of messages
# messages - an array of String
#
# Returns [DateTime, ...]
def message_timestamps(messages)
  messages
    .map { |message| message.match(TIMESTAMP_REGEX)[0] }
    .compact
    .map { |timestamp| DateTime.parse(timestamp) }
end
