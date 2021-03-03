class TestActiveJob < ApplicationJob

  def perform(arg)
    Rails.logger.warn "ActiveJob running with arg=#{arg}"
  end
end