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
require "job_class_helper"
require "active_support"
require "rest_client"

RMQ_API = "http://guest:guest@localhost:15672/api"
RMQ_VHOST_API = "#{RMQ_API}/vhosts/#{AMQP_CONFIG[:vhost]}"
MINIMUM_JOB_DELAY = 0.1

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

  # Truncate the database table and clear the RMQ queues before each spec
  config.before do
    FileUtils.rm(Dir.glob(APP_ROOT.join("tmp", "job*")))
    ActiveRecord::Base.connection.truncate(:delayed_jobs)
    Delayed::Job.tomqueue_manager.queues.values.map(&:name).each do |name|
      RestClient.delete("#{RMQ_API}/queues/#{AMQP_CONFIG[:vhost]}/#{name}/contents")
    end
  end

  config.around(:each, worker: true) do |example|
    begin
      pid = fork do
        if pid.nil?
          TomQueue.bunny = Bunny.new(AMQP_CONFIG)
          TomQueue.bunny.start
          Delayed::Worker.new.start
        end
      end

      unless pid.nil?
        sleep(MINIMUM_JOB_DELAY)
        example.call
      end

    ensure
      Process.kill(:KILL, pid)
    end
  end
end