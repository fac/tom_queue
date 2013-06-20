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

    # Internal: Creates the work object, probably from an AMQP get
    #  response
    #
    # amqp_response - this is the AMQP response object, i.e. the first 
    #                 returned object from @queue.pop
    # header        - this is a hash of headers attached to the message
    # payload       - the raw payload of the message
    #
    def initialize(amqp_response, headers, payload)
      @response = amqp_response
      @headers = headers
      @payload = payload
    end

  end

end