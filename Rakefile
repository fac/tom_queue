
require 'tempfile'
require 'pathname'

# Manage test app instances in the tmp/ directory
#
# Rather than bake lots of test apps, instead this rakefile dynamically creates 
# a test-app of a given framework, ready either to be used as part of automated
# tests, or for development purposes
#
ROOT = Pathname.new(__dir__)
APP_ROOT = ROOT.join("tmp/apps")
RAILS = {
  "6.1.2" => APP_ROOT.join("rails6.1.2"),
  "6.1.3" => APP_ROOT.join("rails6.1.3")
}

# Don't forget, if you change any of these creation steps, you'll need to clean
# and re-create any test apps you have.
namespace :test_app do
  rails_template = Tempfile.new("template")
  rails_template.puts <<~RUBY
    gem("tom_queue", path: "../../..")

    generate(:scaffold, "person name:string")
    
    route "root to: 'people#index'"
    rails_command("generate delayed_job:active_record")

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
    PROCFILE
  RUBY
  rails_template.close

  RAILS.keys.each do |version|
    directory RAILS[version] => APP_ROOT do
      # Install the gem outside of bundler, if it isn't already installed
      sh("gem list -i rails -v #{version} || gem install -v #{version} rails")
      
      # Prepare a rails tree in a "staging" directory (if it fails, we don't want to leave
      # a broken tree in the right place so rake will re-run without having to cleanup)
      stage_root = "#{RAILS[version]}_test_app_stage"
      rm_rf(stage_root)

      sh("rails _#{version}_ new --template=#{rails_template.path} --skip-git --minimal #{stage_root}")

      # Move the (hopefully working) tree into the correct place.
      mv(stage_root, RAILS[version])
    end

    task "start_#{version}" => RAILS[version] do
      cd(RAILS[version]) do
        exec("foreman start")
      end
    end
  end
  
  task :rails => [RAILS["6.1.3"]] do
    puts "rails ready"
    sh("gem install foreman")
  end

  task :clean do
    rm_rf(APP_ROOT)
  end
end