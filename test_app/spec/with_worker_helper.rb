require 'thread'

class Worker
  def initialize
    @worker = Delayed::Worker.new
  end

  def step(count = 1)
    @worker.work_off(count)
  end
end

def with_worker(&block)
  worker = Worker.new
  yield worker
end
