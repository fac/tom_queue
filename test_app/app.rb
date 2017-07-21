require_relative "./config/boot.rb"
require "sinatra"
require "tom_queue"

get "/" do
  redirect "/jobs"
end

get "/jobs" do
  @jobs = Delayed::Job.all
  erb :index, layout: :application
end

post "/jobs" do
  job_klass = eval(params[:type])
  arguments = params[:arguments].split(",")
  Delayed::Job.enqueue(job_klass.new(*arguments))
  redirect "/jobs"
end
