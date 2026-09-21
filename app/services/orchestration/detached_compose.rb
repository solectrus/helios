require 'open3'

module Orchestration
  # Runs a `docker compose up` that includes HELIOS itself, from a helper
  # container. A process inside the HELIOS container cannot survive that
  # container being stopped, so the helper runs independently and outlives the
  # restart.
  #
  # The volume mount must use the HOST path (e.g. /opt/solectrus), not the
  # container-internal data_path (/data), because the helper is a sibling
  # container that mounts directly from the host.
  #
  # Returns as soon as the helper is running. Everything after that happens
  # outside this process, which the converge is about to end.
  #
  # The helper keeps a name and is not removed when it exits, because what it
  # leaves behind is the only account of a run nothing else watched. A run that
  # fails here takes HELIOS down with it, so the exit code and the log of this
  # container are what says why. SelfComposeReport reads them once HELIOS
  # answers again and removes the container then. The name also serves as the
  # lock: two of these runs must not overlap.
  class DetachedCompose
    SERVICE = Runner::SELF_SERVICE

    CONTAINER_NAME = 'helios-self-compose'.freeze

    class << self
      # `services` empty means every service in the compose file, which is what
      # a converge needs: only a run that carries HELIOS *and* the service its
      # port moves to can hand the port over (see SelfPorts).
      def up(services: [], force_recreate: false, remove_orphans: false, prune_images: false)
        clear_previous!
        host_path = Runner.host_data_path
        script = script_for(host_path, services:, force_recreate:, remove_orphans:, prune_images:)
        run_docker(*helper_command(host_path, script))
      end

      private

      # The name is free again for this run. A helper that is still running is
      # a run in flight, and a second one over the same services would fight it
      # for the containers it is building.
      def clear_previous!
        info = DockerCli.inspect_container(CONTAINER_NAME)
        return if info.nil?

        if info.dig('State', 'Running')
          raise Runner::CommandError.new(
            'A self-update or a converge is already running',
            stdout: '',
            exit_status: 1,
          )
        end

        DockerCli.force_remove_container(CONTAINER_NAME)
      end

      def script_for(host_path, services:, force_recreate:, remove_orphans:, prune_images:)
        args = compose_args(host_path, services:, force_recreate:, remove_orphans:)
        script = "docker #{args.join(' ')}"
        prune_images ? "#{script} && docker image prune -f" : script
      end

      def helper_command(host_path, script)
        [
          'docker', 'run', '-d',
          '--name', CONTAINER_NAME,
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

      def compose_args(host_path, services:, force_recreate:, remove_orphans:)
        args = [
          'compose',
          '-f', ::File.join(host_path, ::Compose.filename),
          '--project-directory', host_path
        ]
        if ::File.exist?(::Env.path)
          args.push('--env-file', ::File.join(host_path, '.env'))
        end
        args.push('--progress', 'plain', 'up', '--no-build', '-d')
        args.push('--force-recreate') if force_recreate
        args.push('--remove-orphans') if remove_orphans
        args.concat(services)
      end

      def run_docker(*)
        output, status = Open3.capture2e(*)
        return if status.success?

        raise Runner::CommandError.new(
          "Detached compose failed: #{output}",
          stdout: output,
          exit_status: status.exitstatus,
        )
      end
    end
  end
end
