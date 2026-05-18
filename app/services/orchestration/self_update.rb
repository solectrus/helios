require 'open3'

module Orchestration
  # Self-update: pull the new HELIOS image, then delegate the recreate to a
  # temporary helper container. A process inside the HELIOS container cannot
  # survive the container being stopped, so the helper runs independently and
  # outlives the restart.
  #
  # The volume mount must use the HOST path (e.g. /opt/solectrus), not the
  # container-internal data_path (/data), because the helper is a sibling
  # container that mounts directly from the host.
  class SelfUpdate
    SERVICE = Runner::SELF_SERVICE

    class << self
      def call
        Runner.pull(service: SERVICE)

        host_path = Runner.host_data_path
        script = "docker #{compose_args(host_path).join(' ')} && docker image prune -f"
        run_docker(*helper_command(host_path, script))
      end

      private

      def helper_command(host_path, script)
        [
          'docker', 'run', '--rm', '-d',
          '--entrypoint', 'sh',
          '-v', '/var/run/docker.sock:/var/run/docker.sock',
          '-v', "#{host_path}:#{host_path}",
          helios_image,
          '-c', script
        ]
      end

      def helios_image
        ::Compose.load.services.find(SERVICE).image
      end

      def compose_args(host_path)
        args = [
          'compose',
          '-f', ::File.join(host_path, ::Compose.filename),
          '--project-directory', host_path
        ]
        if ::File.exist?(::Env.path)
          args.push('--env-file', ::File.join(host_path, '.env'))
        end
        args.push(
          '--progress', 'plain',
          'up', '--no-build', '-d', '--force-recreate', SERVICE
        )
      end

      def run_docker(*)
        output, status = Open3.capture2e(*)
        return if status.success?

        raise Runner::CommandError.new(
          "Self-update failed: #{output}",
          stdout: output,
          exit_status: status.exitstatus,
        )
      end
    end
  end
end
