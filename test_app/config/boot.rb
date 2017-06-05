require "pathname"
require "pry-byebug"

APP_ROOT = Pathname.new(File.expand_path("../../", __FILE__))
APP_ENV = ENV["RACK_ENV"] || "development"

require APP_ROOT.join("config", "environments", APP_ENV)
Dir.glob(APP_ROOT.join("config/initializers", "*.rb")) { |file| require file }
Dir.glob(APP_ROOT.join("jobs", "*.rb")) { |file| require file }
