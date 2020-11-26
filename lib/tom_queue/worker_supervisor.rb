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
      $stdout.puts "Starting '#{name}'..."
      process_id = fork do
        after_fork.call
        setup_child_process_signal_handling
        processes[name].call
      end
      self.currently_running_processes[process_id] = name
    end

    def setup_child_process_signal_handling
      # We don't want the child processes to use the signal handlers defined in the parent process
      Signal.trap("TERM", "DEFAULT")
      Signal.trap("INT", "DEFAULT")
      Signal.trap("CHLD", "DEFAULT")
    end

    def stop_child_when_process_finishes
      exit(0)
    end

    def handle_signal_event
      signal = signal_queue.pop
      case signal
      when /CHLD/
        # a child process terminated. Let's remove it from the running processes array so it's started again
        stopped_process_id, status = wait_for_child_process_to_exit
        if stopped_process_name = currently_running_processes.delete(stopped_process_id)
          $stderr.puts "#{stopped_process_name} terminated (#{stopped_process_id}) with status #{status.exitstatus}"
        end
      when /TERM/
        # the supervisor received a termination signal. Let's gracefully shut everything down
        puts "Shutdown!"
        self.stop_loop = true
      end
    end

    def wait_for_child_process_to_exit
      Process.waitpid2
    end

    def throttle_loop
      sleep loop_throttle
    end

    def shut_down_child_processes
      currently_running_processes.keys.each do |pid|
        begin
          Process.kill("TERM", pid)
        rescue Errno::ESRCH
          $stderr.puts "Process already terminated"
        end
      end
    end

    def wait_for_all_child_processes_to_end
      currently_running_processes.keys.each do |pid|
        begin
          Timeout.timeout(graceful_timeout) do
            reaped_pid = Process.waitpid(pid)
            puts "Process #{reaped_pid} reaped"
            next
          end
        rescue Errno::ECHILD
          puts "Process doesn't exist - ignoring"
        rescue Timeout::Error
          puts "Process didn't quit - SIGKILL'ing"
          Process.kill("KILL", pid)
          Process.waitpid(pid)
        end
      end
    end
  end
end
