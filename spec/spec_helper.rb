require 'support/forked_process_helpers'

### DJ

require 'simplecov'
require 'logger'
require 'rspec'

require 'action_mailer'
require 'active_record'

require 'delayed_job'
Delayed::Worker.logger = Logger.new("/tmp/dj.log")
ENV["RAILS_ENV"] = "test"


### DJ::AR

require 'logger'
require 'rspec'
require 'tom_queue'

begin
  require 'protected_attributes'
rescue LoadError
end

require 'delayed/backend/shared_spec'

Delayed::Worker.logger = Logger.new('/tmp/dj.log')
ENV['RAILS_ENV'] = 'test'

db_config = {
  adapter: "mysql2",
  host: "127.0.0.1",
  database: "delayed_job_test",
  username: "root",
  password: ENV.fetch("MYSQL_PASSWORD", "root"),
  encoding: "utf8"
}
ActiveRecord::Base.establish_connection(db_config.slice(:adapter, :host, :username, :password))
ActiveRecord::Base.connection.drop_database(db_config[:database]) rescue nil
ActiveRecord::Base.connection.create_database(db_config[:database], charset: "utf8mb4")
ActiveRecord::Base.establish_connection(db_config)

ActiveRecord::Base.logger = Delayed::Worker.logger
ActiveRecord::Migration.verbose = false


migration_template = File.open("lib/generators/delayed_job/templates/migration.rb")

# need to eval the template with the migration_version intact
migration_context =
  Class.new do
    def my_binding
      binding
    end

    private

    def migration_version
      "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]" if ActiveRecord::VERSION::MAJOR >= 5
    end
  end

migration_ruby = ERB.new(migration_template.read).result(migration_context.new.my_binding)
eval(migration_ruby) # rubocop:disable Security/Eval

ActiveRecord::Schema.define do
  drop_table :delayed_jobs, if_exists: true

  CreateDelayedJobs.up

  create_table :stories, primary_key: :story_id, force: true do |table|
    table.string :text
    table.boolean :scoped, default: true
  end
end

# Purely useful for test cases...
class Story < ActiveRecord::Base
  self.primary_key = 'story_id'
  def tell
    text
  end

  def whatever(n, _)
    tell * n
  end
  default_scope { where(:scoped => true) }

  handle_asynchronously :whatever
end

# Add this directory so the ActiveSupport autoloading works
ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)

RSpec.configure do |config|
  config.example_status_persistence_file_path = "#{__dir__}/../tmp/rspec.failures"

  config.expect_with :rspec do |c|
    c.syntax = [:expect, :should]
  end

  config.after(:each) do
    Delayed::Worker.reset
  end

  config.before do
    Signal.trap("TERM", "DEFAULT")
    Signal.trap("INT", "DEFAULT")
    Signal.trap("CHLD", "DEFAULT")
  end

  [:active_record, :test].each do |backend|
    config.around(backend: backend) do |example|
      old_backend = Delayed::Worker.backend
      Delayed::Worker.backend = backend
      example.call
    ensure
      Delayed::Worker.backend = old_backend
    end
  end
end

### TQ
require 'bunny'
require 'rest_client'
require 'tom_queue'
require 'tom_queue/delayed_job'

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
    TomQueue.logger ||= Logger.new("/dev/null")
    TomQueue::DelayedJob.apply_hook! do
      Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
      example.call
    end
  end

  # Clean up any orphaned process after each test scenario
  r.around do |test|
    TestForkedProcess.wrap(&test)
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
      process = TestForkedProcess.start do
        TomQueue.bunny = Bunny.new(TEST_AMQP_CONFIG)
        TomQueue.bunny.start
        TomQueue::DeferredWorkManager.new(TomQueue.default_prefix).start
      end

      sleep 1

      example.call
    ensure
      process.term
      process.join
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

