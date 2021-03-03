
# The default setup specifies a version as ~> <version>, so let's
# remove that and lock to the version we're installing with
gsub_file "Gemfile", /^gem 'rails'.*$/, ""
gem 'rails', "= #{Rails.version}"

gem("tom_queue", path: "../../..")

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
  job: bundle exec tomqueued
  log: tail -f log/development.log
PROCFILE

file "config/tom_queue_config.rb", <<~CONFIG
  # frozen_string_literal: true

  @tomqueue_supervisor.before_fork = Rails.application.config.before_fork
  @tomqueue_supervisor.after_fork = -> do
    Rails.application.config.after_fork.call
    if Rails.configuration.bunny_queue
      Rails.configuration.bunny_queue.publish_timeout = 2.seconds
      Rails.configuration.bunny_queue.wait_for_start
    end
  end
CONFIG