require 'tom_queue/helper'
require 'tom_queue/delayed_job'

describe "External consumers" do

  let(:exchange_name) { "exchange-#{Time.now.to_f}" }
  let(:consumer_class) do

    # Wah, this hurts, but it does mean we can get the exchange name /into/ the class_eval
    Class.new { include TomQueue::ExternalConsumer }.tap do |klass|
      class << klass
        attr_accessor :messages
      end
      klass.messages = []
      klass.class_eval "bind_exchange(:fanout, \"#{exchange_name}\", :auto_delete => true, :durable => false) { |m| @@messages << m }"
    end
  end

  before do
    # Hopefully break the core consumer loop out of DJ
    TomQueue.default_prefix = "test-prefix"
    TomQueue::DelayedJob.apply_hook!

    TomQueue::DelayedJob.handlers.clear
    TomQueue::DelayedJob.handlers << consumer_class

    Delayed::Job.tomqueue_manager.purge!
  end

  it "should be possible to make a consumer using the TomQueue::ExternalConsumer mixin" do
    consumer_class
  end

  it "should successfully round-trip a message" do
    consumer_class.producer.publish("a message")
    Delayed::Worker.new.work_off(1)
    consumer_class.messages.should == ["a message"]
  end

end







describe "temporary unit tests" do

  it "should clear any priority bindings just in case the priority changes"
  it "should not allow multiple bind_exchange calls to the consumer (for now)"

  describe "exchange options" do
    it "should set the auto-delete if specified"
    it "should default auto-delete to false"

    it "should set the durable flag if specified"
    it "should default durable to true"
  end

  describe "when a message is received" do
    it "should reject the message if an exception is thrown"
    it "should ack the message if the block succeeds"
    it "should re-deliver the message once"
    it "should post the message to a dead-letter queue if the redelivery attempt fails"
  end


  describe "when a block is provided" do

    it "should call the block with received message payload"

  end

  describe "when a block isn't provided" do

    it "should create an instance of the consumer class"
    it "should call #perform on the instance"
    it "should pass the payload as the first argument to the call"

  end


  describe "producer call" do

    it "should return an object that responds to :publish"
    it "should publish a message to the exchange when :publish is called"

  end

end