module TomQueue

  # Internal: This represents a single payload of "work" to 
  #  be completed by the application. You shouldn't create it
  #  directly, but instances will be returned by the 
  #  QueueManager as work is de-queued.
  #
  class Work

    # Public: The payload of the work.
    #
    # This is the serialized string passed to QueueManager#publish
    # and it's up to the application to work out what to do with it!
    attr_reader :payload
    
    # Internal: The set of headers associated with the AMQP message
    #
    # NOTE: Use of these headers directly is discouraged, as their structure
    # is an implementation detail of this library. See Public accessors 
    # below before grabbing data from here.
    #
    # This is a has of string values
    attr_reader :headers

    # Internal: The AMQP response returned when the work was delivered.
    #
    # NOTE: Use of data directly from this response is discouraged, for 
    # the same reason as #headers. It's an implementation detail...
    #
    # Returns an AMQ::Protocol::Basic::GetOk instance
    attr_reader :response

    # Internal: The queue manager to which this work belongs
    attr_reader :manager

    # Internal: Creates the work object, probably from an AMQP get
    #  response
    #
    # queue_manager - the QueueManager object that created this work
    # amqp_response - this is the AMQP response object, i.e. the first 
    #                 returned object from @queue.pop
    # header        - this is a hash of headers attached to the message
    # payload       - the raw payload of the message
    #
    def initialize(queue_manager, amqp_response, headers, payload)
      @manager = queue_manager
      @response = amqp_response
      @headers = headers
      @payload = payload
    end

    # Public: Ack this message, meaning the broker won't attempt to re-deliver 
    # the message.
    #
    # Returns self, so you chain this `pop.ack!.payload` for example
    def ack!
      @manager.ack(self)
      self
    end

    # Public: Reject this message, with a nack (not acked). Optionally re-queue the message
    # or just drop it if requeue == false
    #
    # Returns self
    def nack!(requeue = true)
      @manager.nack(self, requeue)
    end
  end

end
