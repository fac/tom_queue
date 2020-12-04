# frozen_string_literal: true

require 'delayed_job'

if defined?(Rails::Railtie)
  module TomQueue
    class Railtie < Rails::Railtie
      # Migrated from delayed_job/railtie.rb
      initializer "tom_queue.delayed_job" do
        Delayed::Worker.logger ||= if defined?(Rails)
          Rails.logger
        elsif defined?(RAILS_DEFAULT_LOGGER)
          RAILS_DEFAULT_LOGGER
        end
      end

      rake_tasks do
        load 'tom_queue/tasks.rb'
      end

      # Migrated from delayed_job_active_record/railtie.rb
      config.after_initialize do
        require "delayed/backend/active_record"
        Delayed::Worker.backend = :active_record
      end

    end
  end
else
  class TomQueue::Railtie
  end
end