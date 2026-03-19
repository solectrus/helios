class Admin < ApplicationRecord
  has_secure_password

  def self.current
    first
  end

  def self.setup_completed?
    any?
  end

  def self.create_admin!(password:)
    raise 'Admin already exists' if setup_completed?

    create!(password:)
  end
end
