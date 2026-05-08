require 'open3'

module Orchestration
  # Thin wrappers around `docker` invocations shared by the detached
  # backup/restore runners. Each helper returns plain values so callers
  # can raise their own domain-specific errors with their own i18n keys.
  module DockerCli
    RunningContainer = Data.define(:started_at, :args)

    module_function

    def inspect_container(name)
      output, status = Open3.capture2e('docker', 'inspect', name)
      return nil unless status.success?

      JSON.parse(output).first
    rescue JSON::ParserError
      nil
    end

    def running_container(name)
      info = inspect_container(name)
      return nil unless info&.dig('State', 'Running')

      RunningContainer.new(
        started_at: Time.zone.parse(info.dig('State', 'StartedAt')),
        args: Array(info['Args']),
      )
    end

    def image_present?(image)
      _, status = Open3.capture2e('docker', 'image', 'inspect', image)
      status.success?
    end

    def pull_image(image)
      output, status = Open3.capture2e('docker', 'pull', image)
      [status.success?, output]
    end
  end
end
