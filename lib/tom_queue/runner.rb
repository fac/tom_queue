require "serverengine"

require "tom_queue/consumer"

module TomQueue
  class Runner
    attr_reader :consumer, :daemon_builder

    def initialize(args = {})
      @consumer = args.fetch(:consumer, TomQueue::Consumer)
      @daemon_builder = args.fetch(:daemon_builder, ServerEngine.method(:create))
    end

    def start
      daemon.run
    end

    private

    def daemon
      @daemon ||= daemon_builder.call(server, consumer, config)
    end

    def server
      # Intentionally left nil, only for clarity purposes
    end

    def config
      {
        :worker_type => "thread",
        :workers     => 2,
      }
    end
  end
end
