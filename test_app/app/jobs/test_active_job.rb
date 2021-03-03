class TestActiveJob < ApplicationJob
  def perform(arg)
    puts "ActiveJob running with arg=#{arg}"
  end
end