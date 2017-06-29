require 'timeout'
require 'active_support/dependencies'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/class/attribute_accessors'
require 'active_support/hash_with_indifferent_access'
require 'active_support/core_ext/hash/indifferent_access'
require 'logger'
require 'benchmark'

require 'tom_queue/stack'
require 'tom_queue/worker/error_handling'
require 'tom_queue/worker/pop'
require 'tom_queue/worker/delayed_job'
require 'tom_queue/worker/timeout'
require 'tom_queue/worker/invoke'

module TomQueue
  class Worker
    class Stack < TomQueue::Stack
      use ErrorHandling
      use Pop
      use DelayedJob
      use Timeout
      use Invoke
    end

    include LoggingHelper

    DEFAULT_LOG_LEVEL        = 'info'.freeze
    DEFAULT_MAX_ATTEMPTS     = 25
    DEFAULT_MAX_RUN_TIME     = 4.hours
    DEFAULT_DEFAULT_PRIORITY = 0
    DEFAULT_DELAY_JOBS       = true
    DEFAULT_QUEUES           = [].freeze
    DEFAULT_QUEUE_ATTRIBUTES = HashWithIndifferentAccess.new.freeze
    DEFAULT_READ_AHEAD       = 5

    cattr_accessor :min_priority, :max_priority, :max_attempts, :max_run_time,
                   :default_priority, :logger, :delay_jobs, :queues,
                   :read_ahead, :plugins, :destroy_failed_jobs, :exit_on_complete,
                   :default_log_level

    # Named queue into which jobs are enqueued by default
    cattr_accessor :default_queue_name

    # name_prefix is ignored if name is set directly
    attr_accessor :name_prefix

    def self.reset
      self.default_log_level = DEFAULT_LOG_LEVEL
      self.max_attempts      = DEFAULT_MAX_ATTEMPTS
      self.max_run_time      = DEFAULT_MAX_RUN_TIME
      self.default_priority  = DEFAULT_DEFAULT_PRIORITY
      self.delay_jobs        = DEFAULT_DELAY_JOBS
      self.queues            = DEFAULT_QUEUES
      self.read_ahead        = DEFAULT_READ_AHEAD
    end

    # Add or remove plugins in this list before the worker is instantiated
    # self.plugins = [TomQueue::Plugins::ClearLocks]

    # By default failed jobs are destroyed after too many attempts. If you want to keep them around
    # (perhaps to inspect the reason for the failure), set this to false.
    self.destroy_failed_jobs = true

    # By default, Signals INT and TERM set @exit, and the worker exits upon completion of the current job.
    # If you would prefer to raise a SignalException and exit immediately you can use this.
    # Be aware daemons uses TERM to stop and restart
    # false - No exceptions will be raised
    # :term - Will only raise an exception on TERM signals but INT will wait for the current job to finish
    # true - Will raise an exception on TERM and INT
    cattr_accessor :raise_signal_exceptions
    self.raise_signal_exceptions = false

    def self.delay_job?(job)
      if delay_jobs.is_a?(Proc)
        delay_jobs.arity == 1 ? delay_jobs.call(job) : delay_jobs.call
      else
        delay_jobs
      end
    end

    def initialize(options = {})
      @quiet = options.key?(:quiet) ? options[:quiet] : true
      @failed_reserve_count = 0

      [:min_priority, :max_priority, :read_ahead, :queues, :exit_on_complete].each do |option|
        self.class.send("#{option}=", options[option]) if options.key?(option)
      end
    end

    # Every worker has a unique name which by default is the pid of the process. There are some
    # advantages to overriding this with something which survives worker restarts:  Workers can
    # safely resume working on tasks which are locked by themselves. The worker will assume that
    # it crashed before.
    def name
      return @name unless @name.nil?
      "#{@name_prefix}host:#{Socket.gethostname} pid:#{Process.pid}" rescue "#{@name_prefix}pid:#{Process.pid}"
    end

    # Sets the name of the worker.
    # Setting the name to nil will reset the default worker name
    attr_writer :name

    def start # rubocop:disable CyclomaticComplexity, PerceivedComplexity
      trap('TERM') do
        Thread.new { say 'Exiting...' }
        stop
        raise SignalException, 'TERM' if self.class.raise_signal_exceptions
      end

      trap('INT') do
        Thread.new { say 'Exiting...' }
        stop
        raise SignalException, 'INT' if self.class.raise_signal_exceptions && self.class.raise_signal_exceptions != :term
      end

      info 'Starting job worker'

      loop do
        Stack.call(worker: self)
        return if stop?
      end
    end

    def stop
      @exit = true
    end

    def stop?
      !!@exit
    end

    # Do num jobs and return stats on success/failure.
    # Exit early if interrupted.
    def work_off(num = 100)
      success = 0
      failure = 0

      num.times do
        case Stack.call(worker: self)
        when true
          success += 1
        when false
          failure += 1
        else
          break # leave if no work could be done
        end
        break if stop? # leave if we're exiting
      end

      [success, failure]
    end

    def failed(job)
      self.class.lifecycle.run_callbacks(:failure, self, job) do
        begin
          job.hook(:failure)
        rescue => error
          say "Error when running failure callback: #{error}", 'error'
          say error.backtrace.join("\n"), 'error'
        ensure
          job.destroy_failed_jobs? ? job.destroy : job.fail!
        end
      end
    end

    def max_attempts(job)
      job.max_attempts || self.class.max_attempts
    end

    def max_run_time(job)
      job.max_run_time || self.class.max_run_time
    end

  protected

    def handle_failed_job(job, error)
      job.error = error
      job_say job, "FAILED (#{job.attempts} prior attempts) with #{error.class.name}: #{error.message}", 'error'
      reschedule(job)
    end

    def reload!
      return unless self.class.reload_app?
      if defined?(ActiveSupport::Reloader)
        Rails.application.reloader.reload!
      else
        ActionDispatch::Reloader.cleanup!
        ActionDispatch::Reloader.prepare!
      end
    end
  end
end

TomQueue::Worker.reset
