module Env
  def self.load
    return nil unless ::File.exist?(path)

    File.load(path)
  end

  def self.path
    ::File.join(Rails.configuration.data_path, '.env')
  end
end
