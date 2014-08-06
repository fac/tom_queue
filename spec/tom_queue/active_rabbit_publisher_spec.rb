require "spec_helper"
require "tom_queue/active_rabbit_publisher"

describe TomQueue::ActiveRabbitPublisher do

  describe "#initialize" do
    it "requires a handler" do
      expect { TomQueue::ActiveRabbitPublisher.new }.to raise_error(ArgumentError, /handler/)
    end

    it "calls #dup on the handler" do
      handler = double
      expect(handler).to receive(:dup).once

      publisher = TomQueue::ActiveRabbitPublisher.new(handler: handler)
    end
  end

  describe "#topic return value" do
    before do
      @rabbit = ActiveRabbit.new
      @publisher = TomQueue::ActiveRabbitPublisher.new(handler: @rabbit)
      @result = @publisher.topic("champagne")
    end

    it "is an ExchangeWrapper" do
      expect(@result).to be_a_kind_of ActiveRabbit::ExchangeWrapper
    end

    it "wraps the named exchange" do
      expect(@result.exchange_name).to eq "champagne"
    end

    it "responds to #publish" do
      expect(@result).to respond_to(:publish)
    end
  end
end
