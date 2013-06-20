require 'tom_queue/helper'

describe TomQueue::Work do

  let(:work) { TomQueue::Work.new(:response, {'headers' => true}, 'payload') }

  it "should expose the payload" do
    work.payload.should == 'payload'
  end
  it "should expose the headers" do
    work.headers.should == {'headers' => true}
  end
  it "should expose the amqp response object" do
    work.response.should == :response
  end

end
