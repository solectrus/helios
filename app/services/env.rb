module Env
  def self.load
    File.load(path)
  end

  def self.path
    ::File.join(Rails.configuration.helios_stack_path, '.env')
  end
end
