require 'tom_queue/base_helper'
require 'tom_queue/delayed_job'

describe "External consumers without active TomQueue" do

  let(:exchange_name) { "external-exchange-#{Time.now.to_f}" }

  let(:consumer_class) do
    Class.new(Object) { include TomQueue::ExternalConsumer }
  end

  describe "when a consumer is bound to an exchange" do

    before do
      consumer_class.class_exec(exchange_name) do |exchange_name|
        bind_exchange(:fanout, exchange_name, :auto_delete => true, :durable => :false)
      end
    end

    it "should except when publishing" do
      expect { consumer_class.producer.publish('message') }.to raise_error(TomQueue::NotActiveError)
    end
  end
end
