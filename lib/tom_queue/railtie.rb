require 'tom_queue'
require 'rails'

module TomQueue
  class Railtie < Rails::Railtie
    rake_tasks do
      load 'tom_queue/tasks.rb'
    end
  end
end
