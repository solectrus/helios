module DockerHelpers
  def docker_available?
    DockerHost.connected?
  rescue StandardError
    false
  end

  def skip_without_docker
    skip 'Docker not available' unless docker_available?
  end
end

RSpec.configure { |config| config.include DockerHelpers }
