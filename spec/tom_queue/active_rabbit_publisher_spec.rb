require "helper"
begin
  require "active_rabbit"
  require "active_rabbit/testing"
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

    describe "#topic" do
      before do
        rabbit = ActiveRabbit.new
        rabbit.extend ActiveRabbit::TestInstance
        @publisher = described_class.new(handler: rabbit)
      end

      describe "arguments" do
        it "requires the exchange name" do
          expect { @publisher.topic() }.to raise_error(ArgumentError)

          expect(@publisher.topic("name")).to be_a_kind_of(ActiveRabbit::ExchangeWrapper)
        end

        it "optionally accepts exchange options as second argument" do
          expect(@publisher.topic("name", passive: true)).to be_a_kind_of(ActiveRabbit::ExchangeWrapper)
        end
      end

      describe "return value" do
        before do
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
  end
rescue LoadError => e
  # Not running this spec if we can't load in active_rabbit
end
