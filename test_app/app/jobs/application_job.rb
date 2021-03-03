class ApplicationJob < ActiveJob::Base

  before_enqueue do |job|
    JobsChannel.broadcast_to("trace", event: "before_enqueue", job: job)
  end

  after_enqueue do |job|
    JobsChannel.broadcast_to("trace", event: "after_enqueue", job: job)
  end

  before_perform do |job|
    JobsChannel.broadcast_to("trace", event: "before_perform", job: job)
  end
  
  after_perform do |job|
    JobsChannel.broadcast_to("trace", event: "after_perform", job: job)
  end
  
end
