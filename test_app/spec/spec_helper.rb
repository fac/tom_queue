APP_ENV = "test"

require "pry-byebug"
require_relative "../config/boot"
Dir.glob(File.expand_path("../support/*.rb", __FILE__)) { |file| require file }
require "active_support"
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

TomQueue::DelayedJob.priority_map[LOWEST_PRIORITY] = TomQueue::BULK_PRIORITY
TomQueue::DelayedJob.priority_map[LOW_PRIORITY]    = TomQueue::LOW_PRIORITY
TomQueue::DelayedJob.priority_map[NORMAL_PRIORITY] = TomQueue::NORMAL_PRIORITY
TomQueue::DelayedJob.priority_map[HIGH_PRIORITY]   = TomQueue::HIGH_PRIORITY

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
    TomQueue::DelayedJob.apply_hook!
  end
end
