require 'helper'

require 'simplecov'
require 'logger'
require 'rspec'

require 'action_mailer'
require 'active_record'

require 'delayed_job'
Delayed::Worker.logger = Logger.new("/tmp/dj.log")
ENV["RAILS_ENV"] = "test"
