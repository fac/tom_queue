require "fileutils"

TouchFileJob = Struct.new(:name) do
  def perform
    logger = Delayed::Worker.logger
    logger.info "#{Time.new.strftime("%b %d %Y %H:%M:%S")}: [JOB] Touching File #{name}"

    runtime = Benchmark.realtime do
      path = APP_ROOT.join("tmp", name)
      FileUtils.touch(path)
    end

    logger.info "#{Time.new.strftime("%b %d %Y %H:%M:%S")}: [JOB] Touched File #{name} after #{sprintf("%.4f", runtime)}"
  end
end
