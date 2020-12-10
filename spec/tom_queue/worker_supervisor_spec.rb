require "spec_helper"

describe TomQueue::WorkerSupervisor do
  let(:supervisor) { described_class.new }

  let(:forked_supervisor) do
    TestForkedProcess.new do
      supervisor.run
    end
  end

  # This hook ensures that any child processes are coupled to this
  # rspec process by holding open a read file descriptor in a background
  # thread.
  #
  # This is in addition to the child processes being linked to the supervisor
  # process inside WorkerSupervisor.
  before do
    supervisor.after_fork = -> { TestChildProcess.run }
  end

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
    let(:process) { -> { sleep 1 while true } }

    before { supervisor.supervise(as: "worker", &process) }

    it "runs the before hook" do
      before_hook_message = ChildProcessMessage.new
      supervisor.before_fork = -> { before_hook_message.set "executing before fork" }

      forked_supervisor.start

      expect(before_hook_message.wait).to eq "executing before fork"
      forked_supervisor.term
    end

    it "runs the after hook" do
      after_hook_message = ChildProcessMessage.new
      supervisor.after_fork = -> { after_hook_message.set "executing after fork" }

      forked_supervisor.start
      expect(after_hook_message.wait).to eq "executing after fork"

      forked_supervisor.term
    end

    it "runs each process" do
      worker_message = ChildProcessMessage.new
      supervisor.supervise(as: "worker") do
        worker_message.set "executing process 1"
        sleep 1 while true
      end

      deferred_scheduler_message = ChildProcessMessage.new
      supervisor.supervise(as: "deferred scheduler") do
        deferred_scheduler_message.set "executing process 2"
        sleep 1 while true
      end

      forked_supervisor.start

      expect(worker_message.wait).to eq "executing process 1"
      expect(deferred_scheduler_message.wait).to eq "executing process 2"
      forked_supervisor.term
    end

    it "restarts a process if it dies" do
      worker_message = ChildProcessMessage.new

      supervisor.supervise(as: "worker") do
        worker_message.set "executing process 1,"
        exit(1)
      end

      supervisor.loop_throttle = 0.1
      forked_supervisor.start
      sleep 1
      expect(worker_message.wait.split(",").size).to be_between(3,11)
      forked_supervisor.term
    end

    it "does not try to start a process again if it is not dead" do
      worker_message = ChildProcessMessage.new

      supervisor.supervise(as: "worker") do
        worker_message.set "executing process 1"
        sleep 1 while true
      end

      supervisor.loop_throttle = 0.1
      forked_supervisor.start
      sleep 1
      expect(worker_message.wait).to eq "executing process 1"
      forked_supervisor.term
    end

    it "should tightly couple child processes to the supervisor process" do
      worker_message = ChildProcessMessage.new

      supervisor.supervise(as: "worker") do
        worker_message.set "started:#{$$}"
        sleep 1 while true
      end

      forked_supervisor.start
      pid = worker_message.wait.match(/started\:(\d+)/)[1].to_i

      # don't let it clean up
      forked_supervisor.kill
      forked_supervisor.join

      # getpgid (get process group IDs) should work for any PID on the system and
      # return an answer if the process is running. The worker process should
      # have been terminated along with the supervisor, so we want it to return
      # an error
      sleep 0.5
      expect { Process.getpgid(pid) }.to raise_exception(Errno::ESRCH)
    end

    context "signal handling" do
      let(:signals) { Hash.new { |h,k| h[k] = ChildProcessMessage.new }}

      it "propagates termination signals to child processes" do
        signals[:child_ready]
        signals[:exception]

        supervisor.supervise(as: "worker") do
          Signal.trap("SIGTERM") do
            signals[:exception].set("SIGTERM in child")
            raise SignalException, "SIGTERM"
          end
          signals[:child_ready].set("ready")
          sleep 1 while true
        end

        forked_supervisor.start

        expect(signals[:child_ready].wait).to eq("ready")
        forked_supervisor.term
        expect(signals[:exception].wait).to eq("SIGTERM in child")
      end

      it "should SIGKILL the process if it refuses to quit after graceful_timeout" do
        signals[:child_ready]
        signals[:exception]
        supervisor.graceful_timeout = 0.2
        supervisor.supervise(as: "worker") do
          Signal.trap("SIGTERM") do
            signals[:exception].set("SIGTERM in child")
          end
          signals[:child_ready].set("ready")
          sleep 1 while true
        end

        forked_supervisor.start

        expect(signals[:child_ready].wait).to eq("ready")
        forked_supervisor.term

        expect(signals[:exception].wait).to eq("SIGTERM in child")
        forked_supervisor.join
      end

      it "should reset the default signal handlers on child startup" do
        signals[:child_ready]
        signals[:exception]

        supervisor.supervise(as: "worker") do
          # Some signals aren't trappable, so we'll ignore those!
          handlers = (Signal.list.keys - ["EXIT", "PIPE", "SYS", "ILL", "FPE", "KILL", "BUS", "SEGV", "STOP", "VTALRM"]).map do |name|
            [name, Signal.trap(name, "DEFAULT").to_s]
          end
          signals[:child_ready].set(Marshal.dump(handlers))
          sleep 1 while true
        end

        forked_supervisor.start
        Marshal.load(signals[:child_ready].wait).each do |name, handler|
          expect(handler).to eq("DEFAULT").or(eq("SYSTEM_DEFAULT"))
        end
        forked_supervisor.term
      end

      it "doesn't blow up if the process already died" do
        signals[:child_ready]
        signals[:exception]

        supervisor.supervise(as: "worker") do
          Signal.trap("SIGTERM") do
            signals[:exception].set("SIGTERM in child")
          end
          signals[:child_ready].set("ready")
          sleep 1 while true
        end

        # This shouldn't happen, but just in case, we'll simulate a TERM and waitpid
        # happening before our cleanup
        module ShimProcess
          attr_accessor :wonky_kill
          def kill(signal, pid)
            if wonky_kill && ["TERM", "SIGTERM"].include?(signal)
              puts "SIGKILL'ing process before a term"
              super("SIGKILL", pid)
              Process.waitpid(pid)
            end
            super
          end
        end
        class << Process
          prepend(ShimProcess)
        end

        Process.wonky_kill = true
        forked_supervisor.start
        Process.wonky_kill = false

        expect(signals[:child_ready].wait).to eq("ready")
        forked_supervisor.term
        expect(forked_supervisor.join.exitstatus).to eq(0)
      end

      it "should clean up multiple child processes even if it only receives a single SIGCHLD" do
        signals[:child1_ready]
        signals[:child2_ready]

        supervisor.loop_throttle = 0.1

        supervisor.supervise(as: "foo1") do
          puts "Worker1 startup"
          signals[:child1_ready].set("ready:#{$$}")
          sleep 1 while true
        end
        supervisor.supervise(as: "foo2") do
          puts "Worker2 startup"
          signals[:child2_ready].set("ready:#{$$}")
          sleep 1 while true
        end

        forked_supervisor.start

        child1_pid = signals[:child1_ready].wait.match(/\:(\d+)/)[1].to_i
        child2_pid = signals[:child2_ready].wait.match(/\:(\d+)/)[1].to_i

        # now stall the parent process
        forked_supervisor.stop

        # kill both child processes
        Process.kill("KILL", child1_pid)
        Process.kill("KILL", child2_pid)
        sleep 0.2

        # resume the parent process
        forked_supervisor.continue

        new_child1_pid = signals[:child1_ready].wait(5).match(/\:(\d+)/)[1].to_i
        new_child2_pid = signals[:child2_ready].wait(5).match(/\:(\d+)/)[1].to_i

        expect(new_child1_pid).to_not eq(child1_pid)
        expect(new_child2_pid).to_not eq(child2_pid)
      end
    end
  end
end
