module AuthHelpers
  def create_admin
    Admin.create_admin!(password: 'test') unless Admin.exists?
  end

  def delete_admin
    Admin.delete_all
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

  config.before(:all, :with_admin) { create_admin }
  config.after(:all, :with_admin) { delete_admin }

  config.before(:all, :without_admin) { delete_admin }
  config.after(:all, :without_admin) { delete_admin }
end
