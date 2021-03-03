class TestDelayedJob < Struct.new(:arg)

  def perform
    Rails.logger.warn "Delayed job running with arg=#{arg}"
  end 
  
end