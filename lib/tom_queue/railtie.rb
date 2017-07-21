require 'tom_queue'
require 'rails'

module TomQueue
  class Railtie < Rails::Railtie
    initializer :after_initialize do
      ActiveSupport.on_load(:action_mailer) do
        ActionMailer::Base.extend(TomQueue::DelayMail)
      end

      TomQueue::Worker.logger ||= if defined?(Rails)
        Rails.logger
      elsif defined?(RAILS_DEFAULT_LOGGER)
        RAILS_DEFAULT_LOGGER
      end
    end

    rake_tasks do
      load 'tom_queue/tasks.rb'
    end
  end
end
