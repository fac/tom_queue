TestJob = Struct.new(:id, :options) do
  def perform
    log("RUNNING: #{id}")
  end

  def before(job)
    log("BEFORE_HOOK: #{id} Job##{job.id}")
  end

  def after(job)
    log("AFTER_HOOK: #{id} Job##{job.id}")
  end

  def success(job)
    log("SUCCESS_HOOK: #{id} Job##{job.id}")
  end

  def error(job, exception)
    log("ERROR_HOOK: #{id} Job##{job.id} (#{exception.message})")
  end

  def failure(job)
    log("FAILURE_HOOK: #{id} Job##{job.id}")
  end

  private

  def log(message)
    TomQueue.test_logger.debug(message)
  end
end
