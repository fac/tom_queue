require 'helper'
require 'bunny'
require 'tom_queue'

# Patch AR to allow Mock errors to escape after_commit callbacks
# There is a test to check this hook works in delayed_job_spec.rb
require 'active_record/connection_adapters/abstract/database_statements'
module ActiveRecord::ConnectionAdapters::DatabaseStatements
  alias orig_commit_transaction_records commit_transaction_records
  def commit_transaction_records
    records = @_current_transaction_records.flatten
    @_current_transaction_records.clear
    unless records.blank?
      records.uniq.each do |record|
        begin
          record.committed!
        rescue Exception => e
          if e.class.to_s =~ /^RSpec/
            raise
          else
            record.logger.error(e) if record.respond_to?(:logger) && record.logger
          end
        end
      end
    end
  end
end


RSpec.configure do |r|

  r.before do
    TomQueue.exception_reporter = Class.new do
      def notify(exception)
        puts "Exception reported: #{exception.inspect}"
        puts exception.backtrace.join("\n")
      end
    end.new
    
    TomQueue.logger = Logger.new($stdout) if ENV['DEBUG']
  end

  # Make sure all tests see the same Bunny instance
  r.around do |test|
    bunny = Bunny.new(:host => "localhost")
    bunny.start
      
    TomQueue.bunny = bunny
    test.call

    begin
      bunny.close      
    rescue
      puts "Failed to close bunny: #{$!.inspect}"
    ensure
      TomQueue.bunny = nil
    end
  end

  # All tests should take < 2 seconds !!
  r.around do |test|
    timeout = self.class.metadata[:timeout] || 2
    if timeout == false
      test.call
    else
      Timeout.timeout(timeout) { test.call }
    end
  end

  r.around do |test|
    begin
      TomQueue::DeferredWorkManager.reset!

      test.call

    ensure
      # Tidy up any deferred work managers!
      TomQueue::DeferredWorkManager.instances.each_pair do |prefix, i|
        i.ensure_stopped
        i.purge!
      end
      TomQueue::DeferredWorkManager.reset!
    end
  end

end
