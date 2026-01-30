module DockerHost
  class Image
    def self.identifier
      nil
    end

    def self.find(image_ref)
      DockerHost.configure!
      docker_image = fetch_docker_image(image_ref)
      return nil unless docker_image

      build_image(docker_image)
    rescue Docker::Error::NotFoundError, Excon::Error::Socket, Docker::Error::TimeoutError => e
      Rails.logger.debug { "DockerHost::Image.find failed for #{image_ref}: #{e.class}" }
      nil
    end

    def self.fetch_docker_image(image_ref)
      image_ref = "#{image_ref}:latest" unless image_ref.include?(':')
      Docker::Image.get(image_ref)
    end
    private_class_method :fetch_docker_image

    def self.build_image(docker_image)
      image_name = (docker_image.json['RepoTags']&.first || '').split(':').first
      klass = subclasses.find { |c| c.identifier && image_name.include?(c.identifier) } || self
      klass.new(docker_image)
    end
    private_class_method :build_image

    def initialize(docker_image)
      @docker_image = docker_image
    end

    def version
      labels['org.opencontainers.image.version']
    end

    private

    def labels
      @labels ||= @docker_image.json.dig('Config', 'Labels') || {}
    end

    def env
      @env ||= @docker_image.json.dig('Config', 'Env') || []
    end

    def env_value(key)
      env.find { |var| var.start_with?("#{key}=") }&.split('=', 2)&.last
    end
  end
end

Dir[File.join(__dir__, 'image', '*.rb')].each { |f| require f }
