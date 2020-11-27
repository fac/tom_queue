require 'timeout'
module TomQueue
  class WorkerSupervisor

    attr_accessor :after_fork, :before_fork, :graceful_timeout, :processes, :loop_throttle
    attr_reader :currently_running_processes

    def initialize
      @processes = {}
      @currently_running_processes = {}
      @before_fork = -> { }
      @after_fork = -> { }
      @graceful_timeout = 5
      @loop_throttle = 1
    end

    # Public: Adds a number of processes for the supervisor to control
    #
    # as    - The name of the process
    # count - The number of processes we should fork that execute the block
    #         passed in
    # block - The process to supervise
    #
    # Examples
    #
    #   supervise(as: "worker", count: 3) { TomQueue::Worker.new.start }
    #   # => 3
    #
    #   This adds 3 processes that the supervisor will run and keep alive
    #   from the #run method
    #
    #   supervisor.processes
    #   #=> {
    #     "worker1"=>#<Proc:0x00007fa629a41998 (irb):15>,
    #     "worker2"=>#<Proc:0x00007fa629a41998 (irb):15>,
    #     "worker3"=>#<Proc:0x00007fa629a41998 (irb):15>
    #     }
    #
    # Returns the number of processes added
    def supervise(as:, count: 1, &block)
      count.times do |i|
        processes["#{as}#{i + 1}"] = block
      end
    end


    # Public: Starts each process, bringing them back up again if they die.
    #
    # Examples
    #
    #   supervisor = TomQueue::WorkerSupervisor.new
    #   supervisor.supervise(as: "worker") do
    #     loop { p "working..."; sleep 1 }
    #   end
    #
    #   supervisor.supervise(as: "thing that ends") do
    #     1.upto(3) { |i| p "doing thing #{i}"; sleep 1 }
    #   end
    #
    #   supervisor.run
    #
    #   #=>
    #   Starting 'worker1'...
    #   Starting 'thing that ends1'...
    #   "working..."
    #   "doing thing 1"
    #   "working..."
    #   "doing thing 2"
    #   "working..."
    #   "doing thing 3"
    #   "working..."
    #   thing that ends1 terminated (40099) with status 0
    #   "working..."
    #   "working..."
    #   "working..."
    #   Starting 'thing that ends1'...
    #   "doing thing 1"
    #   "working..."
    #   "doing thing 2"
    #   "working..."
    #   "doing thing 3"
    #   "working..."
    #
    def run
      setup_child_linking
      setup_parent_process_signal_handling
      self.stop_loop = false
      self.currently_running_processes = {}

      before_fork.call

      until stop_loop do
        processes_to_start.each do |name|
          fork_process(name)
        end

        # wait for signal event (e.g. SIGTERM/SIGCHLD)
        handle_signal_event

        throttle_loop
      end

      shut_down_child_processes
      wait_for_all_child_processes_to_end
    end

    private

    attr_accessor :signal_queue, :currently_running_processes, :stop_loop

    def setup_parent_process_signal_handling
      @signal_queue = Queue.new

      Signal.trap("TERM") { @signal_queue << "TERM" }
      Signal.trap("CHLD") { @signal_queue << "CHLD" }
    end

    def processes_to_start
      processes.keys - currently_running_processes.values
    end

    def fork_process(name)
      process_id = fork do
        link_child_to_parent
        after_fork.call
        reset_child_process_signal_handlers
        processes[name].call
        exit(0)
      end
      log "Started '#{name}' task as pid #{process_id}"
      self.currently_running_processes[process_id] = name
    end

    def setup_child_linking
      @link_rd, @link_wr = IO.pipe
    end
    def link_child_to_parent
      @link_wr.close
      Thread.new do 
        sleep 1 until @link_rd.read(1).nil?
        log "Supervisor went away unexpectedly, terminating", "child-#{$$}"
        exit(128)
      end
    end

    def reset_child_process_signal_handlers
      # We don't want the child processes to use the signal handlers defined in the parent process
      Signal.trap("TERM", "DEFAULT")
      Signal.trap("INT", "DEFAULT")
      Signal.trap("CHLD", "DEFAULT")
    end

    def handle_signal_event
      signal = signal_queue.pop
      case signal
      when "CHLD"
        # a child process terminated. Let's remove it from the running processes array so it's started again
        while reap_child_process; end
      when "TERM"
        # the supervisor received a termination signal. Let's gracefully shut everything down
        log "Shutdown signal received"
        self.stop_loop = true
      end
    end

    def reap_child_process
      reaped_process_id, status = Process.waitpid2(-1, Process::WNOHANG)
      return false if reaped_process_id.nil?

      if reaped_process_name = currently_running_processes.delete(reaped_process_id)
        log "Task '#{reaped_process_name}' reaped (#{reaped_process_id}) with status #{status.exitstatus}"
        true
      end
    rescue Errno::ECHILD
      false
    end

    def throttle_loop
      sleep loop_throttle
    end

    def shut_down_child_processes
      log "Gracefully shutting down all tasks"
      currently_running_processes.each do |pid, name|
        begin
          Process.kill("TERM", pid)
        rescue Errno::ESRCH
          log "Process '#{name}' (#{pid}) already terminated"
        end
      end
    end

    def wait_for_all_child_processes_to_end
      currently_running_processes.each do |pid, name|
        begin
          Timeout.timeout(graceful_timeout) do
            reap_child_process
          end
        rescue Errno::ECHILD
          log "Task '#{name}' (#{pid}) doesn't exist - ignoring"
        rescue Timeout::Error
          log "Task '#{name}' (#{pid}) shutdown timed out - sending SIGKILL"
          Process.kill("KILL", pid)
          Process.waitpid(pid)
        end
      end
    end

    def log(message, extra=nil)
      extra = ":#{extra}" unless extra.nil?
      $stderr.puts "[WorkerSupervisor#{extra}] #{message}"
    end
  end
end
