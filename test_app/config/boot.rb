require "pathname"
require "tom_queue"
require "delayed_job"
require "delayed_job_active_record"
require "pry-byebug"

APP_ENV ||= ENV["RACK_ENV"] || "development"
APP_ROOT = Pathname.new(File.expand_path("../../", __FILE__))
APP_LOGGER = Logger.new(APP_ROOT.join("log", "#{APP_ENV}.log"))

# DelayedJob wants us to be on rails, so it looks for stuff
# in the rails namespace -- so we emulate it a bit
module Rails
  class << self
    attr_accessor :logger
  end
end
Rails.logger = APP_LOGGER
ActiveRecord::Base.logger = APP_LOGGER

# this is used by DJ to guess where tmp/pids is located (default)
RAILS_ROOT = APP_ROOT

Dir.glob(APP_ROOT.join("config/initializers", "*.rb")) { |file| require file }
Dir.glob(APP_ROOT.join("jobs", "*.rb")) { |file| require file }
require APP_ROOT.join("config", "environments", APP_ENV)
