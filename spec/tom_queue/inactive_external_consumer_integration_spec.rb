require 'tom_queue/helper'
require 'tom_queue/delayed_job'

describe "External consumers without active TomQueue" do

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
    TomQueue.default_prefix = "test-prefix-#{Time.now.to_f}"
    TomQueue::DelayedJob.handlers.clear
    TomQueue::DelayedJob.handlers << consumer_class
  end

  describe "when a consumer is bound to an exchange" do

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
    end

    it "should except when publishing" do
      expect { consumer_class.producer.publish('message') }.to raise_error(TomQueue::NotActiveError)
    end
  end
end
