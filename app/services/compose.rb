module Compose
  FILENAMES = %w[compose.yaml docker-compose.yaml docker-compose.yml].freeze

  # Ensure Docker image references always include an explicit tag.
  # Docker treats "nginx" and "nginx:latest" as identical,
  # but string comparisons need a canonical form.
  def self.normalize_image(image)
    return image if image.nil? || image.include?(':')

    "#{image}:latest"
  end

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
