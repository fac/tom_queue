
# The default setup specifies a version as ~> <version>, so let's
# remove that and lock to the version we're installing with
gsub_file "Gemfile", /^gem 'rails'.*$/, ""
gem 'rails', "= #{Rails.version}"

gem "tom_queue", path: "../../.."

gem "redis"

file "db/migrate/20210301151001_create_delayed_jobs.rb", <<~MIGRATE
  class CreateDelayedJobs < ActiveRecord::Migration[6.1]
    def change

      create_table :delayed_jobs, id: :bigint, unsigned: true do |table|
        table.integer :priority, default: 0, null: false
        table.integer :attempts, default: 0, null: false
        table.text :handler, size: :medium
        table.text :last_error
        table.datetime :run_at
        table.datetime :locked_at
        table.datetime :failed_at
        table.string :locked_by
        table.string :queue
        table.timestamps null: true
      end

      add_index :delayed_jobs, [:priority, :run_at], name: "delayed_jobs_priority"
    end
  end
MIGRATE

rails_command("db:migrate")

file "Procfile", <<~PROCFILE
  web: bundle exec puma -p 3001
  job: bundle exec tomqueued -d -e "./config/tom_queue_config.rb"
  redis: redis-server --port 61379
  log: tail -f log/development.log
PROCFILE

file "config/initializers/active_job.rb", <<~CONFIG
  require "tom_queue/queue_adapter"
  ActiveJob::Base.queue_adapter = :tom_queue
CONFIG

file "config/cable.yml", <<~CONFIG, force: true
  development:
    adapter: redis
    url: redis://127.0.0.1:61379
    channel_prefix: tq_test_app
CONFIG

file "config/tom_queue_config.rb", <<~CONFIG
  # frozen_string_literal: true
  TomQueue.default_prefix = "test"

  @tomqueue_supervisor.before_fork = -> do
    TomQueue.bunny = nil
    #begin
      #Rails.application.config.bunny_queue.stop(timeout: 2)
    #rescue TimeoutError
    #end
  end
  @tomqueue_supervisor.after_fork = -> do
    TEST_AMQP_CONFIG = {:host => 'localhost', :vhost => 'test', :user => 'guest', :password => 'guest'}
    TomQueue.bunny = Bunny.new(TEST_AMQP_CONFIG)
    TomQueue.bunny.start
    ActiveRecord::Base.establish_connection
    Rails.cache.instance_variable_get(:@data).reset unless Rails.application.config.cache_store == :null_store
    #Rails.application.config.bunny_queue.start

    #if Rails.configuration.bunny_queue
      #Rails.configuration.bunny_queue.publish_timeout = 2.seconds
      #Rails.configuration.bunny_queue.wait_for_start
    #end
  end
CONFIG
