source 'https://rubygems.org'

gem 'puma'
gem 'rails', '~> 8.1.3'
gem 'solid_cable'
gem 'solid_queue'
gem 'sqlite3'

# Docker API access
gem 'docker-api'

# Frontend
gem 'rails_vite'
gem 'stimulus-rails'
gem 'turbo-rails'
gem 'view_component'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

group :development, :test do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'capybara'
  gem 'capybara-playwright-driver'
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-capybara', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-rspec_rails', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'webmock'
end

group :development do
  gem 'amazing_print'
  gem 'foreman'
  gem 'herb'
  gem 'syntax_tree'
  gem 'web-console'
end
