require "thor"

require "tom_queue/runner"

module TomQueue
  class CLI < Thor
    desc "work", "Starts consuming jobs from RabbitMQ"
    def work(args = {})
      runner = args.fetch(:runner, TomQueue::Runner)

      runner.new.start
    end
  end
end
