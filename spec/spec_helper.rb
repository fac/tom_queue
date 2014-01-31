require 'bunny'
require 'rest_client'
require 'simplecov'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter
]
SimpleCov.start

begin
  require 'protected_attributes'
rescue LoadError
end

require 'delayed_job_active_record'
require 'delayed/backend/shared_spec'

require 'logger'
Delayed::Worker.logger = Logger.new('/tmp/dj.log')
ENV['RAILS_ENV'] = 'test'

db_adapter, gemfile = ENV["ADAPTER"], ENV["BUNDLE_GEMFILE"]
db_adapter ||= gemfile && gemfile[%r(gemfiles/(.*?)/)] && $1
db_adapter ||= 'mysql'

begin
  config = YAML.load(File.read('spec/database.yml'))
  ActiveRecord::Base.establish_connection config[db_adapter]
  ActiveRecord::Base.logger = Delayed::Worker.logger
  ActiveRecord::Migration.verbose = false

  ActiveRecord::Schema.define do
    create_table :delayed_jobs, :force => true do |table|
      table.integer  :priority, :default => 0
      table.integer  :attempts, :default => 0
      table.text     :handler
      table.text     :last_error
      table.datetime :run_at
      table.datetime :locked_at
      table.datetime :failed_at
      table.string   :locked_by
      table.string   :queue
      table.timestamps
    end

    add_index :delayed_jobs, [:priority, :run_at], :name => 'delayed_jobs_priority'

    create_table :stories, :primary_key => :story_id, :force => true do |table|
      table.string :text
      table.boolean :scoped, :default => true
    end
  end
rescue Mysql2::Error
  if db_adapter == 'mysql'
    $stderr.puts "\033[1;31mException when connecting to MySQL, is it running?\033[0m\n\n"
  end
  raise
end

# Patch AR to allow Mock errors to escape after_commit callbacks
# There is a test to check this hook works in delayed_job_spec.rb
require 'active_record/connection_adapters/abstract/database_statements'
module ActiveRecord::ConnectionAdapters::DatabaseStatements
  alias orig_commit_transaction_records commit_transaction_records
  def commit_transaction_records
    records = @_current_transaction_records.flatten
    @_current_transaction_records.clear
    unless records.blank?
      records.uniq.each do |record|
        begin
          record.committed!
        rescue Exception => e
          if e.class.to_s =~ /^RSpec/
            raise
          else
            record.logger.error(e) if record.respond_to?(:logger) && record.logger
          end
        end
      end
    end
  end
end

# Purely useful for test cases...
class Story < ActiveRecord::Base
  if ::ActiveRecord::VERSION::MAJOR < 4 && ActiveRecord::VERSION::MINOR < 2
    set_primary_key :story_id
  else
    self.primary_key = :story_id
  end
  def tell; text; end
  def whatever(n, _); tell*n; end
  default_scope { where(:scoped => true) }

  handle_asynchronously :whatever
end

# Add this directory so the ActiveSupport autoloading works
ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)

begin
  begin
    RestClient.delete("http://guest:guest@localhost:15672/api/vhosts/test")
  rescue RestClient::ResourceNotFound
  end
  RestClient.put("http://guest:guest@localhost:15672/api/vhosts/test", "{}", :content_type => :json, :accept => :json)
  RestClient.put("http://guest:guest@localhost:15672/api/permissions/test/guest", '{"configure":".*","write":".*","read":".*"}', :content_type => :json, :accept => :json)
  TheBunny = Bunny.new(:host => 'localhost', :vhost => 'test', :user => 'guest', :password => 'guest')
  TheBunny.start
rescue Errno::ECONNREFUSED
  $stderr.puts "\033[1;31mFailed to connect to RabbitMQ, is it running?\033[0m\n\n"
  raise
end

require 'tom_queue'
require 'tom_queue/delayed_job'

RSpec.configure do |rspec|
  rspec.treat_symbols_as_metadata_keys_with_true_values = true
  rspec.run_all_when_everything_filtered = true
  rspec.filter_run :focus
  rspec.order = "random"

  rspec.before do
    TomQueue.exception_reporter = Class.new {
      def method_missing(*args)
      end
    }.new

    # Make sure all tests see the same Bunny instance
    TomQueue.bunny = TheBunny

    if ENV['DEBUG']
      TomQueue.logger = Logger.new($stdout)
    else
      TomQueue.logger ||= Logger.new("/dev/null")
      TomQueue.default_prefix = "test-#{Time.now.to_f}"
    end

    TomQueue::DelayedJob.apply_hook!
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
  end

  # All tests should take < 2 seconds !!
  rspec.around do |test|
    timeout = self.class.metadata[:timeout] || 2
    if timeout == false
      test.call
    else
      Timeout.timeout(timeout) { test.call }
    end
  end

  rspec.around do |test|
    begin
      TomQueue::DeferredWorkManager.reset!

      test.call

    ensure
      TomQueue::DeferredWorkManager.reset!
    end
  end
end
