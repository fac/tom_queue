class JobsChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "jobs:trace"
  end

  def unsubscribed
  end
end
