module AuthHelpers
  def set_admin_password(password = 'test')
    ENV['ADMIN_PASSWORD'] = password
  end

  def clear_admin_password
    ENV.delete('ADMIN_PASSWORD')
  end

  # For request tests
  def login
    post session_path, params: { password: 'test' }
  end

  # For system tests (browser-based)
  def sign_in
    visit new_session_path
    fill_in 'password', with: 'test'
    click_on 'Login'
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system
  config.include AuthHelpers, type: :channel

  config.before(:each, :with_admin_password) { set_admin_password }
  config.after(:each, :with_admin_password) { clear_admin_password }

  config.before(:each, :without_admin_password) { clear_admin_password }
end
