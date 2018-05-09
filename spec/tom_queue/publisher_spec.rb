require 'tom_queue/helper'

describe TomQueue::Publisher do

  subject(:publisher) { TomQueue::Publisher.new }

  let(:channel) { double(:channel) }
  let(:exchange) { double(:exchange) }

  it "publishes the message to an exchange" do
    expect(TomQueue.bunny).to receive(:create_channel).and_return(channel)
    expect(channel).to receive(:exchange).with("myexchange", { foo: :bar, type: :fanout }).and_return(exchange)
    expect(exchange).to receive(:publish).with("mymessage", { bar: :foo })

    publisher.publish(
      TomQueue.bunny,
      exchange_type: :fanout,
      exchange_name: "myexchange",
      exchange_options: { foo: :bar },
      message_payload: "mymessage",
      message_options: { bar: :foo }
    )
  end
end
