$stderr.puts "require 'delayed_job_active_record' is deprecated, migrate to require 'tom_queue'"
caller.each { |e| $stderr.puts "\t#{e}"}

require "delayed_job"
require 'active_record'
require "delayed/backend/active_record"

Delayed::Worker.backend = :active_record
