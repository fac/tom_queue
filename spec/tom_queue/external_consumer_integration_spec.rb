require 'tom_queue/helper'
require 'tom_queue/delayed_job'

describe "External consumers" do

  let(:exchange_name) { "external-exchange-#{Time.now.to_f}" }
  let(:trace) { [] }

  let(:consumer_class) do
    Class.new(Object) { include TomQueue::ExternalConsumer }.tap { |k| k.class_exec(trace) do |trace|
      self::Trace = trace
      def self.trace(*stuff); self::Trace << stuff; end
      def trace(*stuff); self.class.trace(*stuff); end
    end }
  end

  before do
    # Hopefully break the core consumer loop out of DJ
    TomQueue.default_prefix = "test-prefix-#{Time.now.to_f}"

    TomQueue::DelayedJob.handlers.clear
    TomQueue::DelayedJob.handlers << consumer_class
  end

  subject { Delayed::Worker.new.work_off(2) }

  it "should be possible to make a consumer using the TomQueue::ExternalConsumer mixin" do
    consumer_class
  end

  describe "when a consumer is bound to an exchange without a block" do

    before do
      consumer_class.class_exec(exchange_name) do |exchange_name|

        bind_exchange(:fanout, exchange_name, :auto_delete => true, :durable => :false)

        def initialize(payload, headers)
          @payload = payload
          trace(:init, payload, headers)
        end

        def perform
          trace(:perform, @payload)
        end

      end

      consumer_class.producer.publish('message')
      subject
    end

    it "should call the init and perform methods the consumer" do
      expect(trace.map { |a| a[0] }).to eq [:init, :perform]
    end

    it "should call the init method with the payload and headers" do
      trace.first.tap do |method, payload, headers|
        expect(method).to eq :init
        expect(payload).to eq 'message'
        expect(headers).to be_a(Hash)
      end
    end

    it "should have serialized the class so ivars from init are available during the perform call" do
      expect(trace.last).to eq [:perform, 'message']
    end
  end

  describe "when a block is attached to the bind_exchange call" do

    before do
      consumer_class.class_exec(exchange_name) do |exchange_name|

        bind_exchange(:fanout, exchange_name, :auto_delete => true, :durable => :false) do |work|
          trace(:bind_block, work)
          self.block_method(work)
        end

        def self.block_method(work)
          "something other than a delayed job"
        end

      end

      consumer_class.producer.publish('message')
    end

    it "should call the block attached to the bind_exchange call" do
      subject
      expect(trace.first.first).to eq :bind_block
    end

    it "should pass the TomQueue::Work object to the block" do
      subject
      trace.first.last.tap do |work|
        expect(work).to be_a(TomQueue::Work)
        expect(work.payload).to eq 'message'
      end
    end

    describe "if something other than a Delayed::Job instance is returned" do
      xit "should ack the original AMQP message" do
        pending('...')
      end
    end

    describe "if the block returns a Delayed::Job instance" do

      before do
        consumer_class.class_eval do
          def self.block_method(work)
            new('custom-arg').delay.perform
          end

          def initialize(arg)
            trace(:init, arg)
          end
          def perform
            trace(:job_performed)
          end
        end
      end

      it "should call the bind block, which calls the init and defers the perform call" do
        subject
        expect(trace.map { |a| a[0] }).to eq [:bind_block, :init, :job_performed]
      end

      it "should be init'd directly with the custom arguments" do
        subject
        expect(trace[1].last).to eq 'custom-arg'
      end

      it "should perform the Delayed::Job" do
        subject
        expect(trace.last).to eq [:job_performed]
      end

    end

  end

  it "passes the configured routing key through to the exchange on publication" do
    consumer_class.class_exec(exchange_name) do |exchange_name|
      bind_exchange(:topic, exchange_name, :routing_key => "my.key") do |work|
        trace(:bind_block, work)
      end
    end
    consumer_class.producer.publish('message')
    subject
    expect(trace.last[1].response.routing_key).to eq "my.key"
  end

  it "overrides the configured routing key through to the exchange on publication" do
    consumer_class.class_exec(exchange_name) do |exchange_name|
      bind_exchange(:topic, exchange_name) do |work|
        trace(:bind_block, work)
      end
    end
    consumer_class.producer.publish('message', :routing_key => "better.key")
    subject
    expect(trace.last[1].response.routing_key).to eq "better.key"
  end

  it "matches any routing key by default on message publication" do
    consumer_class.class_exec(exchange_name) do |exchange_name|
      bind_exchange(:topic, exchange_name) do |work|
        trace :routing_key, work.response.routing_key
      end
    end
    consumer_class.producer.publish('message', :routing_key => "good.key")
    Delayed::Worker.new.work_off(2)
    consumer_class.producer.publish('message', :routing_key => "better.key")
    Delayed::Worker.new.work_off(2)
    consumer_class.producer.publish('message')
    Delayed::Worker.new.work_off(2)
    expect(trace).to include [:routing_key, "good.key"]
    expect(trace).to include [:routing_key, "better.key"]
    expect(trace).to include [:routing_key, ""]
  end


  it "should use the encoder if specified"


#   it "should not re-deliver the message once the delayed job has been created"





#   it "should raise an exception if you publish a message without having bound the consumer"
#   it "should raise an exception if you try to bind a consumer twice"


#   it "should successfully round-trip a message" do
#     consumer_class.producer.publish("a message")
#     Delayed::Worker.new.work_off(1)
#     consumer_class.messages.should == ["a message"]
#   end

#   it "should republish a message if an exception is raised" do
#     consumer_class.producer.publish("asplode")
#     consumer_class.asplode_count = 1
#     Delayed::Worker.new.work_off(2)
#     consumer_class.messages.should == ["asplode"]
#   end

#   it "should immediately run a job if one is returned out of the block"


#   describe "if an exception is thrown by two workers" do
#     it "should push the message to a dead-letter queue if an exception is raised twice"
#     it "should trigger a log message"
#     it "should notify the exception reporter"
#   end

# end

# describe "temporary unit tests" do

#   it "should clear any priority bindings just in case the priority changes"
#   it "should not allow multiple bind_exchange calls to the consumer (for now)"

#   describe "exchange options" do
#     it "should set the auto-delete if specified"
#     it "should default auto-delete to false"

#     it "should set the durable flag if specified"
#     it "should default durable to true"
#   end

#   describe "when a message is received" do
#     it "should reject the message if an exception is thrown"
#     it "should ack the message if the block succeeds"
#     it "should re-deliver the message once"
#     it "should post the message to a dead-letter queue if the redelivery attempt fails"
#   end


#   describe "when a block is provided" do

#     it "should call the block with received message payload"

#   end

#   describe "when a block isn't provided" do

#     it "should create an instance of the consumer class"
#     it "should call #perform on the instance"
#     it "should pass the payload as the first argument to the call"

#   end


#   describe "producer call" do

#     it "should return an object that responds to :publish"
#     it "should publish a message to the exchange when :publish is called"

#   end

end
