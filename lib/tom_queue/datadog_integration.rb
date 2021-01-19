require 'ddtrace/contrib/delayed_job/integration'

module Datadog
  module Contrib
    module DelayedJob
      class TomQueueIntegration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.0.0.pre2')

        register_as :delayed_job

        def self.version
          Gem.loaded_specs['tom_queue'] && Gem.loaded_specs['tom_queue'].version
        end

        def self.loaded?
          !defined?(::Delayed).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
