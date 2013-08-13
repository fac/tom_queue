require 'helper'
require 'bunny'
require 'rest_client'
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

begin
  RestClient.delete("http://guest:guest@localhost:15672/api/vhosts/test")
rescue RestClient::ResourceNotFound
end
RestClient.put("http://guest:guest@localhost:15672/api/vhosts/test", "{}", :content_type => :json, :accept => :json)
RestClient.put("http://guest:guest@localhost:15672/api/permissions/test/guest", '{"configure":".*","write":".*","read":".*"}', :content_type => :json, :accept => :json)
TheBunny = Bunny.new(:host => 'localhost', :vhost => 'test', :user => 'guest', :password => 'guest')
TheBunny.start

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
  r.before do |test|
    TomQueue.bunny = TheBunny
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
