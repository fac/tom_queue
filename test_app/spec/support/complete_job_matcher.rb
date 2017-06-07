MAX_TIMEOUT = 5

def expect_message(message, seconds)
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

RSpec::Matchers.define :complete do
  match do |payload|
    expect_message("SUCCESS_HOOK: #{payload.id}", @timeout)
  end

  chain :within do |seconds|
    @timeout = seconds
  end
end

RSpec::Matchers.define :error do
  match do |payload|
    expect_message("ERROR_HOOK: #{payload.id}", @timeout)
  end

  chain :within do |seconds|
    @timeout = seconds
  end
end
