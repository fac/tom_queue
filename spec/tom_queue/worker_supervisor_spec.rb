require 'tom_queue/helper'
require "pry"
require 'tom_queue/worker_supervisor'

describe TomQueue::WorkerSupervisor do
  let(:supervisor) { described_class.new }

  let(:forked_supervisor) do
    TestForkedProcess.new do
      supervisor.run
    end
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

    context "signal handling" do
      let(:signals) { Hash.new { |h,k| h[k] = ChildProcessMessage.new }}

      before do
        supervisor.after_fork = -> { TestChildProcess.run }
      end

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
          handlers = (Signal.list.keys - ["ILL", "FPE", "KILL", "BUS", "SEGV", "STOP", "VTALRM"]).map do |name|
            Signal.trap(name, "DEFAULT")
          end
          signals[:child_ready].set(handlers.uniq.compact.join(","))
          sleep 1 while true
        end

        forked_supervisor.start
        expect(signals[:child_ready].wait).to eq("DEFAULT,SYSTEM_DEFAULT")
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
    end
  end
end
