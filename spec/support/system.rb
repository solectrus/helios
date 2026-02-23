require 'capybara/rspec'
require 'capybara-playwright-driver'

Capybara.register_driver :my_playwright do |app|
  Capybara::Playwright::Driver.new(
    app,
    browser_type: :chromium,
    headless: ENV['HEADLESS'] != 'false',
  )
end

Capybara.default_driver = :my_playwright
Capybara.save_path = Rails.root.join('tmp/capybara')

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :my_playwright

    page.current_window.resize_to(1280, 800)
  end
end
