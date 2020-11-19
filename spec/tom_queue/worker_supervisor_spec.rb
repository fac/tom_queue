require "pry"
require 'tom_queue/worker_supervisor'

describe TomQueue::WorkerSupervisor do
  let(:supervisor) { described_class.new }

  describe "#supervise" do
    it "creates a process with the right name" do
      supervisor.supervise(as: "worker") { }
      expect(supervisor.processes.keys).to include "worker1"
    end

    it "creates a process with the specified behaviour" do
      my_proc = -> {}
      supervisor.supervise(as: "worker", &my_proc)
      expect(supervisor.processes.values).to include my_proc
    end

    it "can create multiple processes" do
      supervisor.supervise(as: "worker", count: 2) { }
      supervisor.supervise(as: "deferred_worker") { }
      expect(supervisor.processes.keys).to match_array ["worker1", "worker2", "deferred_worker1"]
    end
  end

  describe "#before_fork" do
    it "assigns the before_fork task" do
      before_fork_task = -> { }
      supervisor.before_fork = before_fork_task
      expect(supervisor.before_fork).to eq before_fork_task
    end
  end

  describe "#after_fork" do
    it "assigns the after_fork task" do
      after_fork_task = -> { }
      supervisor.after_fork = after_fork_task
      expect(supervisor.after_fork).to eq after_fork_task
    end
  end

  describe "#run" do
    let(:process) do
      -> do
        loop do
        end
      end
    end

    before { supervisor.supervise(as: "worker", &process) }

    it "runs the before hook" do
      before_hook_message = ChildProcessMessage.new("before hook")
      before_fork_task = -> { before_hook_message.write_in_child_process }
      supervisor.before_fork = before_fork_task

      supervisor_process = fork do
        supervisor.run
        exit(0)
      end
      sleep 1
      Process.kill("TERM", supervisor_process)
      before_hook_message.expect_message_was_written
    end

    it "runs the after hook" do
      after_hook_message = ChildProcessMessage.new("executing after fork")
      after_fork_task = -> { after_hook_message.write_in_child_process }
      supervisor.after_fork = after_fork_task

      supervisor_process = fork do
        supervisor.run
        exit(0)
      end
      sleep 1
      Process.kill("TERM", supervisor_process)
      after_hook_message.expect_message_was_written
    end

    it "runs each process" do
      worker_message = ChildProcessMessage.new("executing process 1")
      supervisor.supervise(as: "worker") do
        worker_message.write_in_child_process
        exit(0)
      end

      deferred_scheduler_message = ChildProcessMessage.new("executing process 2")
      supervisor.supervise(as: "deferred scheduler") do
        deferred_scheduler_message.write_in_child_process
        exit(0)
      end

      supervisor_process = fork do
        supervisor.run
      end

      sleep 1
      Process.kill("TERM", supervisor_process)

      worker_message.expect_message_was_written
      deferred_scheduler_message.expect_message_was_written
    end

    it "restarts a process if it dies" do
      worker_message = ChildProcessMessage.new("executing process 1")
      supervisor.supervise(as: "worker") do
        worker_message.write_in_child_process
        exit(1)
      end

      supervisor_process = fork do
        supervisor.run
      end

      # TODO: sleeping is hack
      sleep 2
      Process.kill("TERM", supervisor_process)

      worker_message.expect_message_was_written(times: 2)
    end

    it "does not try to start a process again if it is not dead" do
      worker_message = ChildProcessMessage.new("executing process 1")

      supervisor.supervise(as: "worker") do
        worker_message.write_in_child_process
        loop do
        end
      end

      supervisor_process = fork do
        supervisor.run
      end

      # TODO: sleeping is hack
      sleep 2
      Process.kill("TERM", supervisor_process)

      worker_message.expect_message_was_written(times: 1)
    end

    context "signal handling" do
      it "propagates termination signals to child processes" do
        signal_message = ChildProcessMessage.new("trapped TERM signal")
        child_process = -> do
          Signal.trap("SIGTERM") do
            signal_message.write_in_child_process
            raise SignalException, "SIGTERM"
          end
          loop do
          end
        end

        supervisor.supervise(as: "worker", &child_process)

        supervisor_process = fork do
          supervisor.run
        end
        sleep 2

        Process.kill("SIGTERM", supervisor_process)
        signal_message.expect_message_was_written
      end
    end

    class ChildProcessMessage
      include RSpec::Matchers

      def initialize(message)
        @message = message
        @read, @write = IO.pipe
      end

      def write_in_child_process
        @read.close
        @write.write @message
        @write.close
      end

      def expect_message_was_written(times: 1)
        @write.close
        expect(@read.gets).to eq @message*times
        @read.close
      end
    end
  end
end
