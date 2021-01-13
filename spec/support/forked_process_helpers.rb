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

Thread.abort_on_exception = true

# This hook ensures that any child processes are coupled to this
# rspec process by holding open a read file descriptor in a background
# thread.
#
# This is in addition to the child processes being linked to the supervisor
# process inside WorkerSupervisor.
class TestForkedProcess
  attr_reader :pid

  # yields the given block and ensures any TestForkedProcesses
  # are cleaned up after
  def self.wrap
    Thread.current[:processes] = []
    yield
  ensure
    while a = Thread.current[:processes].pop
      begin
        a.term
        a.join(timeout: 5)
      rescue Timeout::Error
        a.kill
        a.join
      end
    end
    Thread.current[:processes] = nil
  end

  @@rd, @@wr = IO.pipe
  def self.attach_child
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

  def initialize(&block)
    @block = block
  end

  def self.start(&block)
    new(&block).tap { |i| i.start }
  end

  def start
    Thread.current[:processes]&.push(self)
    @pid = fork do
      TestForkedProcess.attach_child
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

  def join(timeout: false)
    if timeout
      Timeout.timeout(timeout) { join(timeout: false) }
    else
      _, status = Process.waitpid2(@pid)
      status
    end
  ensure
    Thread.current[:processes]&.delete(self)
  end

end


