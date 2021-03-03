class JobsController < ApplicationController

  def index
    @jobs = Delayed::Job.all
    render partial: "list" if params[:fragment] == 'list'
  end

  def create
    Delayed::Job.enqueue(TestDelayedJob.new("some-arg"))
    TestActiveJob.perform_later("some-arg")
    redirect_to new_job_path
  end

end
