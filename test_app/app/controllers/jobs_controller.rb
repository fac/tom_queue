class JobsController < ApplicationController

  def index
    @jobs = Delayed::Job.all
    render partial: "list" if params[:fragment] == 'list'
  end

  def create
    Delayed::Job.enqueue(TestDelayedJob.new("some-arg"), run_at: run_at)
    TestActiveJob.set(wait_until: run_at).perform_later("some-arg")
    redirect_to new_job_path
  end

  private

  def run_at
    10.minutes.from_now if params[:deferred]
  end
end
