MAX_TIMEOUT = 5

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

def message(message, seconds)
  received = false
  Timeout.timeout(seconds || MAX_TIMEOUT) do
    while !received do
      output = TomQueue.test_logger.readline
      received = !!(output =~ /#{Regexp.escape(message)}/)
    end
  end
  true
rescue Timeout::Error
  false
end
