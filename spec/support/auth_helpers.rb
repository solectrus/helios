module AuthHelpers
  def set_admin_password(password = 'test')
    @admin_password = password
  end

  def clear_admin_password
    @admin_password = nil
  end

  def admin_password_for_config
    @admin_password
  end

  # For request tests
  def login
    with_config_yaml unless config_yaml_dir
    post session_path, params: { password: @admin_password || 'test' }
  end

  # For system tests (browser-based)
  def sign_in
    with_config_yaml unless config_yaml_dir
    visit new_session_path
    fill_in 'password', with: @admin_password || 'test'
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
