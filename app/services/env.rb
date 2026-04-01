module Env
  def self.load
    File.load(path)
  end

  def self.path
    ::File.join(Rails.configuration.data_path, '.env')
  end
end
