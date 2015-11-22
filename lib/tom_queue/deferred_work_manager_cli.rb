$stdout.sync = true

require "optparse"
require "tom_queue"

module TomQueue

  class DeferredWorkManagerCLI
    include LoggingHelper

    def initialize
      @autoload_rails = true
      @require_paths = []
    end

    def run(argv = ARGV)
      parse_options(argv)

      load_app

      deferred_manager = DeferredWorkManager.new
      deferred_manager.start
    end

    def parse_options(args = ARGV)
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: deferred_work_manager [options]"

        opts.on("-v", "--version", "Show the version of Tom Queue") do
          puts TomQueue::VERSION
          exit
        end

        opts.on("--[no-]autoload_rails", "Whether to load the Rails app") do |autoload_rails|
          @autoload_rails = autoload_rails
        end

        opts.on("--require_path PATH", "The path of app/lib to require") do |path|
          @require_paths << path
        end

        opts.on("-h", "--help", "List the functionality") do
          puts opts
          exit
        end
      end

      parser.parse!(args)
    end

    def load_app
      load_rails!(".") if @autoload_rails

      @require_paths.each do |path|
        next if load_rails!(path)

        begin
          info "Loading #{path} ..."
          require path
        rescue Exception => ex
          puts "#{ex.class}: #{ex.message}"
          fatal "#{ex.class}: #{ex.message}"
          exit 1
        end
      end
    end

    # Load Rails environment
    #
    # Returns true/false indicate whether Rails is loaded or not
    def load_rails!(path)
      rails_env_path = File.expand_path(File.join(path, 'config/environment.rb'))

      if File.exists?(rails_env_path)
        info "Loading Rails from env file: #{rails_env_path}"
        ENV['RACK_ENV'] = ENV['RAILS_ENV'] ||= "development"
        require rails_env_path
        ::Rails.application.eager_load!
        true
      else
        false
      end
    end
  end
end
