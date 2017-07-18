# coding: utf-8

require_relative "lib/tom_queue/version"

Gem::Specification.new do |spec|
  spec.add_dependency   'activerecord', '~> 4.1'
  spec.add_dependency   'activesupport'
  spec.add_dependency   'actionmailer', '>= 4.1'
  spec.add_dependency   'bunny', "~> 2.2"
  spec.authors        = ["Thomas Haggett"]
  spec.description    = 'Delayed Job compatible background job processor'
  spec.email          = ['thomas+gemfiles@freeagent.com']
  spec.files          = %w(tom_queue.gemspec)
  spec.files         += Dir.glob("lib/**/*.rb")
  spec.files         += Dir.glob("spec/**/*")
  spec.homepage       = 'http://github.com/fac/tom_queue'
  spec.licenses       = ['MIT']
  spec.name           = 'tom_queue'
  spec.require_paths  = ['lib']
  spec.summary        = 'Delayed Job compatible background job processor'
  spec.test_files     = Dir.glob("spec/**/*")
  spec.version        = TomQueue::VERSION

  spec.add_development_dependency('rest-client')
end
