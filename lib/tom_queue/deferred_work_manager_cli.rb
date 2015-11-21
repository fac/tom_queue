module TomQueue
  class DeferredWorkManagerCLI
    require "optparse"
    require "tom_queue/version"

    def initialize
    end

    def run(argv = ARGV)
      parse_options(argv)
    end

    def parse_options(args = ARGV)
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: deferred_work_manager [options]"

        opts.on("-v", "--version", "Show the version of Tom Queue") do
          puts TomQueue::VERSION
          exit
        end
      end

      parser.parse!(args)
    end
  end
end
