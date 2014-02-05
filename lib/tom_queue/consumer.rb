require 'serverengine'

module TomQueue
  module Consumer
    def initialize
      @stop_flag = ServerEngine::BlockingFlag.new
    end

    def run
      until stop?
        logger.info "I'm consuming"
        sleep 1
      end
    end

    def stop
      @stop_flag.set!
    end

    def stop?
      @stop_flag.set?
    end
  end
end
