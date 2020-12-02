require 'helper'
require 'bunny'
require 'rest_client'
require 'tom_queue'
require 'tom_queue/delayed_job'

require_relative '../support/forked_process_helpers'

#
# Temporary note:
#
# Needs RabbitMQ running with management interface enabled, to get it booted in a docker container:
#
#  docker pull rabbitmq:3-management
#  docker run -d -p 5672:5672 -p 15672:15672 --name rmq-server rabbitmq:3-management
#
# To shutdown:
#
#  docker kill rmq-server
#

begin
  begin
    RestClient.delete("http://guest:guest@localhost:15672/api/vhosts/test")
  rescue RestClient::ResourceNotFound
  end
  RestClient.put("http://guest:guest@localhost:15672/api/vhosts/test", "{}", :content_type => :json, :accept => :json)
  RestClient.put("http://guest:guest@localhost:15672/api/permissions/test/guest", '{"configure":".*","write":".*","read":".*"}', :content_type => :json, :accept => :json)
  TEST_AMQP_CONFIG = {:host => 'localhost', :vhost => 'test', :user => 'guest', :password => 'guest'}
  TheBunny = Bunny.new(TEST_AMQP_CONFIG)
rescue Errno::ECONNREFUSED
  $stderr.puts "\033[1;31mFailed to connect to RabbitMQ, is it running?\033[0m\n\n"
  raise
end


module SlowExpectation
  def within(timeout)
    start_time = Time.now
    yield
  rescue RSpec::Expectations::ExpectationNotMetError
    sleep 0.5
    if Time.now > start_time + timeout
      raise
    else
      retry
    end
  end
end


RSpec.configure do |r|
  r.include(SlowExpectation)
  r.before do
    TomQueue.exception_reporter = Class.new do
      def notify(exception)
        puts "Exception reported: #{exception.inspect}"
        puts exception.backtrace.join("\n")
      end
    end.new

    TomQueue.logger = Logger.new($stdout) if ENV['DEBUG']
  end

  # Make sure all tests see the same Bunny instance
  r.before do |test|
  end

  r.around do |test|
    TomQueue.default_prefix = "test-#{Time.now.to_f}"
    TomQueue.publisher = TomQueue::Publisher.new
    TheBunny.start
    TomQueue.bunny = TheBunny
    test.call
    TheBunny.stop
  end

  r.around(dj_hook: true) do |example|
    TomQueue::DelayedJob.apply_hook!(&example)
  end

  r.before do
    TomQueue.logger ||= Logger.new("/dev/null")
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
  end

  # All tests should take < 2 seconds !!
  r.around do |test|
    timeout = self.class.metadata[:timeout] || 2
    if timeout == false
      test.call
    else
      Timeout.timeout(timeout) { test.call }
    end
  end

  r.around(:each, deferred_work_manager: true) do |example|
    begin
      pid = fork do
        TomQueue.bunny = Bunny.new(TEST_AMQP_CONFIG)
        TomQueue.bunny.start
        TomQueue::DeferredWorkManager.new(TomQueue.default_prefix).start
      end

      sleep 1

      example.call
    ensure
      Process.kill(:KILL, pid)
    end
  end
end

def unacked_message_count(priority)
  queue_name = Delayed::Job.tomqueue_manager.queues[priority].name
  response = RestClient.get("http://guest:guest@localhost:15672/api/queues/test/#{queue_name}", :accept => :json)
  JSON.parse(response)["messages_unacknowledged"]
end

def queue_exists?(queue_name)
  response = RestClient.get("http://guest:guest@localhost:15672/api/queues/test/#{queue_name}", :accept => :json)
  true
rescue RestClient::NotFound
  false
end
