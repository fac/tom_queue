DummyJob = Struct.new(:id) do
  def self.flag_file
    APP_ROOT.join("tmp", "job#{self.object_id}")
  end

  def self.completed?
    File.exists?(self.flag_file)
  end

  def self.reset!
    FileUtils.rm(self.flag_file, force: true)
  end

  def perform
    FileUtils.touch(self.class.flag_file)
  rescue
  end
end

def job_class
  Class.new(DummyJob)
end

RSpec::Matchers.define :complete_within do |seconds|
  match do |job_class|
    begin
      Timeout.timeout(seconds) do
        while !job_class.completed?
          sleep(0.05)
        end
      end
      true
    rescue Timeout::Error
      false
    end
  end
end
