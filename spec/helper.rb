require 'logger'
require 'rspec'

begin
  require 'protected_attributes'
rescue LoadError
end
require 'delayed_job_active_record'
require 'delayed/backend/shared_spec'

Delayed::Worker.logger = Logger.new('/tmp/dj.log')
ENV['RAILS_ENV'] = 'test'


# db_adapter, gemfile = ENV["ADAPTER"], ENV["BUNDLE_GEMFILE"]
# db_adapter ||= gemfile && gemfile[%r(gemfiles/(.*?)/)] && $1
# db_adapter ||= 'mysql'

# begin
#   config = YAML.load(File.read('spec/database.yml'))
#   db_config = config[db_adapter]
#   ActiveRecord::Base.establish_connection(db_config.slice(*%w{adapter host username password}))
#   ActiveRecord::Base.connection.drop_database(db_config["database"]) rescue nil
#   ActiveRecord::Base.connection.create_database(db_config["database"], charset: "utf8mb4")
#   ActiveRecord::Base.establish_connection(db_config)

#   ActiveRecord::Base.logger = Delayed::Worker.logger
#   ActiveRecord::Migration.verbose = false

#   ActiveRecord::Schema.define do
#     create_table :delayed_jobs, :force => true do |table|
#       table.integer  :priority, :default => 0
#       table.integer  :attempts, :default => 0
#       table.text     :handler
#       table.text     :last_error
#       table.datetime :run_at
#       table.datetime :locked_at
#       table.datetime :failed_at
#       table.string   :locked_by
#       table.string   :queue
#       table.timestamps null: false
#     end

#     add_index :delayed_jobs, [:priority, :run_at], :name => 'delayed_jobs_priority'

#     create_table :stories, :primary_key => :story_id, :force => true do |table|
#       table.string :text
#       table.boolean :scoped, :default => true
#     end
#   end
# rescue Mysql2::Error
#   if db_adapter == 'mysql'
#     $stderr.puts "\033[1;31mException when connecting to MySQL, is it running?\033[0m\n\n"
#   end
#   raise
# end

# # Purely useful for test cases...
# class Story < ActiveRecord::Base
#   if ::ActiveRecord::VERSION::MAJOR < 4 && ActiveRecord::VERSION::MINOR < 2
#     set_primary_key :story_id
#   else
#     self.primary_key = :story_id
#   end
#   def tell; text; end
#   def whatever(n, _); tell*n; end
#   default_scope { where(:scoped => true) }

#   handle_asynchronously :whatever
# end

# # Add this directory so the ActiveSupport autoloading works
# ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)
