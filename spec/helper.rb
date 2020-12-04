require 'logger'
require 'rspec'
require 'tom_queue'

begin
  require 'protected_attributes'
rescue LoadError
end

require 'active_record'
require 'delayed_job'

require 'delayed/backend/shared_spec'

Delayed::Worker.logger = Logger.new('/tmp/dj.log')
ENV['RAILS_ENV'] = 'test'

db_config = {
  adapter: "mysql2",
  host: "127.0.0.1",
  database: "delayed_job_test",
  username: "root",
  password: "root",
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
