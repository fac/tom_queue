require 'timeout'
module TomQueue
  class WorkerSupervisor

    attr_accessor :processes, :before_fork, :after_fork

    def initialize
      @processes = {}
      @before_fork = -> { }
      @after_fork = -> { }
      @graceful_timeout = 5
    end

    def supervise(as:, count: 1, &block)
      count.times do |i|
        processes["#{as}#{i + 1}"] = block
      end
    end

    attr_accessor :graceful_timeout

    def run
      @queue = Queue.new

      Signal.trap("TERM") { @queue << "TERM" }
      Signal.trap("CHLD") { @queue << "CHLD" }

      process_ids = {}
      before_fork.call
      loop do
        processes_to_start = (processes.keys - process_ids.values)

        processes_to_start.each do |name|
          $stdout.puts "Starting '#{name}'..."
          process_id = fork_process(name)
          process_ids[process_id] = name
        end

        event = @queue.pop
        puts "Got signal event #{event}"
        case event
        when "CHLD"
          stopped_process_id, status = wait_for_child_process_to_exit
          if stopped_process_name = process_ids.delete(stopped_process_id)
            $stderr.puts "#{stopped_process_name} terminated (#{stopped_process_id}) with status #{status.exitstatus}"
          end
        when "TERM"
          puts "Shutdown!"
          break
        end

        throttle_loop
      end

      puts "cleanly shutting down supervisor process!"
      process_ids.keys.each do |pid|
        begin
          Process.kill("TERM", pid)
        rescue Errno::ESRCH
          $stderr.puts "Process already terminated"  
        end
      end
      puts "Waiting #{@graceful_timeout} for processes to exit"
      process_ids.keys.each do |pid|
        begin
          Timeout.timeout(@graceful_timeout) do
            reaped_pid = Process.waitpid(pid)
            puts "Process #{reaped_pid} reaped"
            next
          end
        rescue Errno::ECHILD
          puts "Process doesn't exist - ignoring"
        rescue Timeout::Error
          puts "PRocess didn't quit - SIGKILL'ing"
          Process.kill("KILL", pid)
          Process.waitpid(pid)
        end
      end
    end

    private

    attr_accessor :stop

    def fork_process(name)
      fork do
        Signal.trap("TERM", "DEFAULT")
        Signal.trap("INT", "DEFAULT")
        Signal.trap("CHLD", "DEFAULT")
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
