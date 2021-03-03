class TestingController < ApplicationController

  # GET / is routed here
  def index

  end

  # POST /action is routed here
  def action
    Delayed::Job.enqueue(TestDelayedJob.new("some-arg"))
    TestActiveJob.new("some-arg").perform_later
    redirect_to "/"
  end

end
