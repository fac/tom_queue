require 'tom_queue/helper'
require 'tom_queue/delayed_job'

describe "Binding to external exchanges" do
  before do
    TomQueue.logger ||= Logger.new("/dev/null")
    TomQueue.default_prefix = "default-prefix"
    TomQueue::DelayedJob.apply_hook!
  end

  class MyHandlerClass
    def self.amqp_binding
      {
        :exchange    => "test-exchange",
        :routing_key => '#',
        :priority    => TomQueue::NORMAL_PRIORITY
      }
    end

    def self.on_message(message)
      puts "Got a message!"
    end
  end

  before do
    TomQueue::DelayedJob.handlers << MyHandlerClass

    # This will trigger the handler to be setup
    Delayed::Job.class_variable_set(:@@tomqueue_manager, nil)
    Delayed::Job.tomqueue_manager.purge!
  end

  it "should allow external classes to be registered" do
  end

  it "should call on_message for any message received to the specified exchange / routing_key" do
    MyHandlerClass.should_receive(:on_message).with("payload").once

    TomQueue.bunny.fanout('test-exchange').publish("payload")

    Delayed::Worker.new.work_off(1)
  end

end