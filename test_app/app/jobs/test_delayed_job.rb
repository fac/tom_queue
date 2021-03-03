class TestDelayedJob < Struct.new(:arg)

  def perform
    puts "Delayed job running with arg=#{arg}"
  end 
  
end