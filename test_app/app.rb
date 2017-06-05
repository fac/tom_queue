require "sinatra"

get "/" do
  redirect "/jobs"
end

get "/jobs" do
  erb :index, layout: :application
end

post "/jobs" do

end

get "/jobs/:id" do

end
