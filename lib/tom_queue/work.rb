module TomQueue

  # Internal: This represents a single payload of "work" to 
  #  be completed by the application. You shouldn't create it
  #  directly, but instances will be returned by the 
  #  QueueManager as work is de-queued.
  #
  class Work

    attr_reader :payload
    def initialize(payload)
      @payload = payload
    end

  end

end