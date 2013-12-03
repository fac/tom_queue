# coding: utf-8

Gem::Specification.new do |spec|
  spec.add_dependency   'activerecord', '~> 3.2.15'
  spec.add_dependency   'delayed_job_active_record'
  spec.add_dependency   'bunny', '~> 0.9.0'
  spec.authors        = ["Thomas Haggett"]
  spec.description    = 'AMQP hook for Delayed Job, backed by ActiveRecord'
  spec.email          = ['thomas+gemfiles@freeagent.com']
  spec.files          = %w(tom_queue.gemspec)
  spec.files         += Dir.glob("lib/**/*.rb")
  spec.files         += Dir.glob("spec/**/*")
  spec.homepage       = 'http://github.com/fac/tom_queue'
  spec.licenses       = ['MIT']
  spec.name           = 'tom_queue'
  spec.require_paths  = ['lib']
  spec.summary        = 'AMQP hook for ActiveRecord backend for DelayedJob'
  spec.test_files     = Dir.glob("spec/**/*")
  spec.version        = '0.0.1.dev'

  spec.add_development_dependency('rest-client')
end
