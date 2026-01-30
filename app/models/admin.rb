class Admin < ApplicationRecord
  has_secure_password

  def self.current
    first
  end

  def self.exists?
    any?
  end

  def self.create_admin!(password:)
    raise 'Admin already exists' if exists?

    create!(password:)
  end
end
