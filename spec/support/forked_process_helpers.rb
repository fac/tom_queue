class ChildProcessMessage
  include RSpec::Matchers

  def initialize(message=nil)
    @message = message
    @read, @write = IO.pipe
  end

  # sets a value in the child process to be communicated 
  # back to the waiting parent process.
  def set(value)
    @read.close
    @write.write value
  end

  # to be called in the parent process, waiting for the child
  # to set a value
  def wait(timeout=2)
    @write.close
    @read.read_with_timeout(timeout)
  end
end

class IO
  def read_with_timeout(t)
    rd,_,_ = IO.select([self], nil, nil, t)
    if rd&.include?(self)
      self.read_nonblock(1024)
    else
      raise "Timeout"
    end
  rescue EOFError
    nil
  end 
end

class TestForkedProcess
  attr_reader :pid

  def initialize(&block)
    @block = block
  end

  def start
    @pid = fork do
      TestChildProcess.run
      @block.call
    end
  end

  def term
    Process.kill("SIGTERM", @pid)
  end

  def stop
    Process.kill("SIGSTOP", @pid)
  end

  def continue
    Process.kill("SIGCONT", @pid)
  end


  def kill
    Process.kill("SIGKILL", @pid)
  end

  def join
    _, status = Process.waitpid2(@pid)
    status
  end

end

Thread.abort_on_exception = true
class TestChildProcess
  @@rd, @@wr = IO.pipe

  def self.run
    @@wr.close
    Thread.new do
      loop do
        if @@rd.read(1).nil? 
          puts " ** Cleaning up orphaned child #{$$}"
          exit(1)
        end
      end
    end
    yield if block_given?
  end
end

