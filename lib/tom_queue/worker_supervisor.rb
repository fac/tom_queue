module TomQueue
  class WorkerSupervisor

    attr_accessor :processes, :before_fork, :after_fork

    def initialize
      @processes = {}
      @before_fork = -> { }
      @after_fork = -> { }
    end

    def supervise(as:, count: 1, &block)
      count.times do |i|
        processes["#{as}#{i + 1}"] = block
      end
    end

    def run
      @stop = false
      process_ids = {}
      before_fork.call
      loop do
        processes_to_start = (processes.keys - process_ids.values)

        processes_to_start.each do |name|
          $stdout.puts "Starting '#{name}'..."
          process_id = fork_process(name)
          setup_signal_handling_for_process(process_id)
          process_ids[process_id] = name
        end

        stopped_process_id, status = wait_for_child_process_to_exit

        if stopped_process_name = process_ids.delete(stopped_process_id)
          $stderr.puts "#{stopped_process_name} terminated (#{stopped_process_id}) with status #{status.exitstatus}"
        end

        throttle_loop
        break if @stop
      end
    end

    private

    attr_accessor :stop

    def setup_signal_handling_for_process(process_id)
      Signal.trap("SIGTERM") do
        $stdout.puts "trapped signal SIGTERM"
        begin
          Process.kill("SIGTERM", process_id)
        rescue Errno::ESRCH
          # Child PID already dead
          $stderr.puts "Tried to kill child process with id #{process_id}, but it was already dead"
        end
        raise SignalException, "SIGTERM"
      end
    end

    def fork_process(name)
      fork do
        execute_child_process(processes[name])
      end
    end

    def execute_child_process(process)
      after_fork.call
      process.call
      stop_child_when_process_finishes
    end

    def stop_child_when_process_finishes
      exit(0)
    end

    def wait_for_child_process_to_exit
      Process.waitpid2
    end

    def throttle_loop
      sleep 1
    end
  end
end
