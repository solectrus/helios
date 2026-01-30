module Compose
  FILENAMES = %w[compose.yaml docker-compose.yaml docker-compose.yml].freeze

  def self.load
    File.load(path)
  end

  def self.path
    stack_path = Rails.configuration.helios_stack_path
    FILENAMES.each do |filename|
      full_path = ::File.join(stack_path, filename)
      return full_path if ::File.exist?(full_path)
    end
    # Default to compose.yaml if none exists
    ::File.join(stack_path, 'compose.yaml')
  end
end
