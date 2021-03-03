require 'tempfile'
require 'pathname'

# Manage test app instances in the tmp/ directory
#
# Rather than bake lots of test apps, instead this rakefile dynamically creates 
# a test-app of a given framework, ready either to be used as part of automated
# tests, or for development purposes
#

# Don't forget, if you change any of these creation steps, you'll need to clean
# and re-create any test apps you have.
namespace :test_app do

  ROOT = Pathname.new(__dir__).join("..")
  APP_ROOT = ROOT.join("tmp/apps")
  RAILS = {
    "6.1.2" => APP_ROOT.join("rails6.1.2"),
    "6.1.3" => APP_ROOT.join("rails6.1.3")
  }
  RAILS_ARGS = "-T -G -S -J --skip-spring --skip-listen --skip-bootsnap"
  RAILS_LINKS = {
    "app" => "app",
    "config/amqp.yaml" => "amqp.yml",
    "config/routes.rb" => "routes.rb"
  }

  task "foreman" do
    sh("gem list -i rails || gem install foreman")
  end

  RAILS.keys.each do |version|
    task "build_#{version}"

    directory RAILS[version] => APP_ROOT do
      # Install the gem outside of bundler, if it isn't already installed
      sh("gem list -i rails -v #{version} || gem install -v #{version} rails")
      
      # Prepare a rails tree in a "staging" directory (if it fails, we don't want to leave
      # a broken tree in the right place so rake will re-run without having to cleanup)
      stage_root = Pathname.new("#{RAILS[version]}_test_app_stage")
      rm_rf(stage_root)
      sh("rails _#{version}_ new #{RAILS_ARGS} --template=#{ROOT.join("test_app/template.rb")} #{stage_root}")
  
      # Remove all files we're going to symlink into place
      RAILS_LINKS.keys.each do |path|
        rm_rf(stage_root.join(path))
      end

      # Move the (hopefully working) tree into the correct place.
      mv(stage_root, RAILS[version])
    end
    task "build_#{version}" => RAILS[version]

    # For each symlink file, build a dedicated rake task
    RAILS_LINKS.each do |target, source|
      file RAILS[version].join(target) => RAILS[version] do
        ln_s ROOT.join("test_app").join(source), RAILS[version].join(target)
      end
      task "build_#{version}" => RAILS[version].join(target)
    end

    task "start_#{version}" => [:foreman, "build_#{version}"] do
      cd(RAILS[version]) do
        exec("foreman start")
      end
    end

    task :rails => "build_#{version}"
  end
  
  task :rails do
    puts "rails ready"
  end

  task :clean do
    rm_rf(APP_ROOT)
  end
end