require "helper"

begin
  require "tom_queue/stomp_publisher"

  describe TomQueue::StompPublisher do

    let(:publisher) { TomQueue::StompPublisher.new(:stomp_config => {}) }

    describe "#initialize" do
      it "requires stomp_config" do
        expect { TomQueue::StompPublisher.new }.to raise_error(ArgumentError)
      end
    end

    describe "#topic" do
      describe "arguments" do
        it "requires the exchange name" do
          expect { publisher.topic }.to raise_error(ArgumentError)
          expect { publisher.topic("name") }.not_to raise_error
        end

        it "optionally accepts exchange options as second argument" do
          expect { publisher.topic("name", :blah => true, :foo => false) }.not_to raise_error
        end
      end

      describe "return value" do
        let(:result) { publisher.topic("champagne") }

        it "knows the exchange it represents" do
          expect(result.exchange_name).to eq("champagne")
        end

        it "responds to #publish" do
          expect(result).to respond_to(:publish)
        end
      end
    end

    describe "#publish" do
      let(:client) { double(Stomp::Client) }
      let(:exchange) { publisher.topic("champagne") }
      before { publisher.instance_variable_set(:@client, client) }

      it "publishes a basic message to the exchange" do
        expect(client).to receive(:publish).with("/exchange/champagne", "superduper", {})

        exchange.publish("superduper")
      end

      it "publishes a routed message to the exchange" do
        expect(client).to receive(:publish).with("/exchange/champagne/supernova", "superduper", {})

        exchange.publish("superduper", key: "supernova")
      end

      it "publishes with custom message headers" do
        expect(client).to receive(:publish).with("/exchange/champagne", "superduper", {run_at: 9001})

        exchange.publish("superduper", headers: {run_at: 9001})
      end
    end

  end
rescue LoadError => e
  # Not running this spec if we can't load in active_rabbit
end
