source 'https://rubygems.org'

gem 'rake'

gem 'rspec', '~> 3.6'
gem 'simplecov'

gem 'sqlite3'
gem 'mysql2', '~> 0.3.13'

gem 'activerecord', ENV.fetch("activerecord_VERSION", '~> 4.2')
gem 'bunny',        ENV.fetch("bunny_VERSION", '~> 2.2')

group :development, :test do
  gem "pry"
end

gemspec
