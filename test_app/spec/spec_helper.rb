# This file was generated by the `rspec --init` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# The generated `.rspec` file contains `--require spec_helper` which will cause
# this file to always be loaded, without a need to explicitly require it in any
# files.
#
# Given that it is always loaded, you are encouraged to keep this file as
# light-weight as possible. Requiring heavyweight dependencies from this file
# will add to the boot time of your test suite on EVERY test run, even for an
# individual file that may not need all of that loaded. Instead, consider making
# a separate helper file that requires the additional dependencies and performs
# the additional setup, and require it from the spec files that actually need
# it.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
APP_ENV = "test"

require_relative "../config/boot"
Dir.glob(File.expand_path("../support/*.rb", __FILE__)) { |file| require file }
require "rest_client"
require "rspec/wait"

RMQ_API = "http://guest:guest@localhost:15672/api"
RMQ_VHOST_API = "#{RMQ_API}/vhosts/#{AMQP_CONFIG[:vhost]}"
MINIMUM_JOB_DELAY = 0.1

JOB_PRIORITIES = [
  LOWEST_PRIORITY   = 2,
  LOW_PRIORITY      = 1,
  NORMAL_PRIORITY   = 0,
  HIGH_PRIORITY     = -1
]

TomQueue.priority_map[LOWEST_PRIORITY] = TomQueue::BULK_PRIORITY
TomQueue.priority_map[LOW_PRIORITY]    = TomQueue::LOW_PRIORITY
TomQueue.priority_map[NORMAL_PRIORITY] = TomQueue::NORMAL_PRIORITY
TomQueue.priority_map[HIGH_PRIORITY]   = TomQueue::HIGH_PRIORITY

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Database setup
  config.before(:suite) do
    db_config = YAML.load_file(APP_ROOT.join("config", "database.yml"))[APP_ENV]

    # Drop and recreate the database
    ActiveRecord::Base.establish_connection(db_config.slice(*%w{adapter host username password}))
    ActiveRecord::Base.connection.drop_database(db_config["database"]) rescue nil
    ActiveRecord::Base.connection.create_database(db_config["database"])
    ActiveRecord::Base.establish_connection(db_config)

    # Set up the schema
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
        table.timestamps null: false
      end

      add_index :delayed_jobs, [:priority, :run_at], :name => 'delayed_jobs_priority'
    end
  end

  # RMQ setup
  config.before(:suite) do
    RestClient.delete("#{RMQ_VHOST_API}") rescue RestClient::ResourceNotFound
    RestClient.put("#{RMQ_VHOST_API}", "{}", :content_type => :json, :accept => :json)
    RestClient.put("#{RMQ_API}/permissions/#{AMQP_CONFIG[:vhost]}/#{AMQP_CONFIG[:user]}", '{"configure":".*","write":".*","read":".*"}', :content_type => :json, :accept => :json)

    TomQueue.bunny = Bunny.new(AMQP_CONFIG)
    TomQueue.bunny.start
    TomQueue.config[:override_enqueue] = ENV["NEUTER_DJ"] || false
    TomQueue.config[:override_worker] = native_worker?
    TomQueue::DelayedJob.apply_hook!
  end

  config.before do
    TomQueue.logger = Logger.new($stdout) if ENV['DEBUG']
  end
end

def native_worker?
  ENV["NEUTER_DJ"] || false
end
