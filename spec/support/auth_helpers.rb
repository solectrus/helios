module AuthHelpers
  def create_admin
    Admin.create_admin!(password: 'test') unless Admin.exists?
  end

  def delete_admin
    Admin.delete_all
  end

  def login
    post session_path, params: { password: 'test' }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request

  config.before(:all, :with_admin) { create_admin }
  config.after(:all, :with_admin) { delete_admin }

  config.before(:all, :without_admin) { delete_admin }
  config.after(:all, :without_admin) { delete_admin }
end
