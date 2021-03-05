class TestDelayedJob < Struct.new(:arg)

  class FailAndRetry < Exception
  end

  def perform
    Rails.logger.warn "Delayed job running with arg=#{arg}"
    raise "oops"
  end

  def reschedule_at(current_time, attempts)
    Rails.logger.info("We're rescheduling the job!")
    current_time + attempts.seconds
  end

  def max_attempts
    3
  end

  def destroy_failed_jobs
    true
  end

  def before(job)
    log("Before job")
  end

  def after(job)
    log("After job")
  end

  def success(job)
    log("Success")
  end

  def error(job, exception)
    log("Error: #{exception}")
  end

  def failure(job)
    log("Fail")
  end

  def log(msg)
    Rails.logger.info("TEST_DELAYED_JOB:#{msg}")
  end
end
