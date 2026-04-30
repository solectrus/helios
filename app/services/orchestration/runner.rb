require 'open3'

module Orchestration
  class Runner
    class CommandError < StandardError
      attr_reader :stdout, :stderr, :exit_status

      def initialize(message, stdout: '', stderr: '', exit_status: nil)
        super(message)
        @stdout = stdout
        @stderr = stderr
        @exit_status = exit_status
      end
    end

    SELF_SERVICE = 'helios'.freeze

    class << self
      def up(detach: true)
        validate_data_path!

        # --remove-orphans clears containers that linger after a service
        # rename (e.g. legacy 'app' → canonical 'dashboard' from import).
        # Compose only deletes containers carrying its own project label,
        # so user-launched sidecars are not affected.
        args = %w[up --no-build --remove-orphans]
        args << '-d' if detach
        args.concat(services_except_self)
        result = run_compose(*args)
        cleanup_images!
        result
      end

      def down(remove_volumes: false)
        args = ['down']
        args << '-v' if remove_volumes
        args.concat(services_except_self)
        run_compose(*args)
      end

      def pull(service: nil)
        args = ['pull']
        args << service if service
        run_compose(*args)
      end

      def recreate(service)
        previous_image = Orchestration::Container.find(service)&.image
        pull(service:)
        run_compose('down', service.to_s)
        result = run_compose('up', '--no-build', '-d', service.to_s)
        cleanup_images!(previous_image:)
        result
      end

      # Self-update: pull new image, then delegate the recreate to
      # a temporary helper container. A process inside the HELIOS
      # container cannot survive the container being stopped, so the
      # helper runs independently and outlives the restart.
      #
      # The volume mount must use the HOST path (e.g. /opt/solectrus),
      # not the container-internal data_path (/data), because the helper
      # is a sibling container that mounts directly from the host.
      def self_recreate
        pull(service: SELF_SERVICE)

        compose = ::Compose.load
        image = compose.services.find(SELF_SERVICE).image
        host_path = host_data_path
        script = "docker #{self_recreate_compose_args(host_path).join(' ')} && docker image prune -f"

        cmd = [
          'docker', 'run', '--rm', '-d',
          '--entrypoint', 'sh',
          '-v', '/var/run/docker.sock:/var/run/docker.sock',
          '-v', "#{host_path}:#{host_path}",
          image,
          '-c', script
        ]
        run_docker(*cmd)
      end

      def start(*services)
        args = %w[up --no-build -d]
        args.concat(services.flatten.compact)
        run_compose(*args)
      end

      def stop(service)
        args = ['down']
        args << service
        run_compose(*args)
      end

      def logs(
        service: nil,
        tail: nil,
        follow: false,
        timestamps: false,
        until_timestamp: nil
      )
        args = ['logs']
        args << '-f' if follow
        args << '--timestamps' if timestamps
        # --tail and --until cannot be combined (Docker ignores --until when --tail is set)
        args += ['--tail', tail.to_s] if tail && !until_timestamp
        args += ['--until', until_timestamp.to_s] if until_timestamp
        args << service if service
        run_compose(*args)
      end

      # Streams log lines from `docker compose logs -f`.
      # Returns [io, pid]. Caller is responsible for reading
      # from io and killing the process when done.
      def stream_logs(service:, tail: 0)
        validate_data_path!

        cmd =
          build_compose_command(
            'logs',
            '-f',
            '--timestamps',
            '--tail',
            tail.to_s,
            service.to_s,
          )
        io = IO.popen(cmd, err: %i[child out])

        [io, io.pid]
      end

      def config_hashes
        result = run_compose('config', '--hash', '*')
        result.output.each_line.to_h do |line|
          name, hash = line.strip.split
          [name, hash]
        end
      end

      def ps
        run_compose('ps')
      end

      def data_path
        Rails.configuration.data_path
      end

      private

      def run_compose(*args)
        validate_data_path!

        cmd = build_compose_command(*args)
        output, status = Open3.capture2e(*cmd)

        raise_command_error(args.first, output, status) unless status.success?

        CommandResult.new(output:, exit_status: status.exitstatus)
      end

      def build_compose_command(*args)
        cmd = [
          'docker',
          'compose',
          '-f',
          ::Compose.path,
          '--project-directory',
          host_data_path,
        ]
        env_path = ::Env.path
        cmd.push('--env-file', env_path) if ::File.exist?(env_path)
        cmd.push('--progress', 'plain')
        cmd + args.map(&:to_s)
      end

      def raise_command_error(subcommand, output, status)
        raise CommandError.new(
                "docker compose #{subcommand} failed: #{output}",
                stdout: output,
                stderr: '',
                exit_status: status.exitstatus,
              )
      end

      def validate_data_path!
        path = data_path

        if path.blank?
          raise CommandError,
                'Data path not configured.'
        end

        return if Dir.exist?(path)

        raise CommandError, "Data path does not exist: #{path}"
      end

      def run_docker(*args)
        output, status = Open3.capture2e(*args)
        raise_command_error(args.first, output, status) unless status.success?
      end

      def self_recreate_compose_args(host_path)
        args = [
          'compose',
          '-f', ::File.join(host_path, 'compose.yaml'),
          '--project-directory', host_path
        ]
        if ::File.exist?(::Env.path)
          args.push('--env-file', ::File.join(host_path, '.env'))
        end
        args.push(
          '--progress', 'plain',
          'up', '--no-build', '-d', '--force-recreate', SELF_SERVICE
        )
      end

      # In production, data_path (e.g. /data) is container-internal; the Docker
      # daemon runs on the host and needs the real host path to resolve bind-mount
      # sources in compose.yaml. In dev/test, data_path is already a host path.
      def host_data_path
        return data_path unless Rails.env.production?

        source = Orchestration::Container.find(SELF_SERVICE)&.mount_source(data_path)
        raise CommandError, "Cannot resolve HELIOS host mount for #{data_path}" unless source

        source
      end

      def services_except_self
        ::Compose.load.services.names - [SELF_SERVICE]
      end

      # Stopped services are intentionally skipped — the user may still
      # need their images. We never pass --force, so any image still
      # referenced by a container survives.
      def cleanup_images!(previous_image: nil)
        prune_images(previous_image) if previous_image.present?
        prune_legacy_for_running_services
        prune_dangling_images
      end

      def prune_images(*images)
        return if images.empty?

        Open3.capture2e('docker', 'image', 'rm', *images)
      end

      def prune_legacy_for_running_services
        Orchestration::Container.invalidate_cache
        running = Orchestration::Container.all.select(&:running?)
        in_use = running.map(&:image)
        tags = running.flat_map { |c| known_tags_for(c.service_name) }.uniq - in_use
        prune_images(*tags)
      end

      def known_tags_for(service_name)
        DockerImages.known_for(service_name).flat_map do |entry|
          entry.include?(':') ? [entry] : tags_for_repo(entry)
        end
      end

      def tags_for_repo(repo)
        output, status =
          Open3.capture2e('docker', 'images', repo, '--format', '{{.Repository}}:{{.Tag}}')
        return [] unless status.success?

        output.lines.map(&:strip).reject { |line| line.empty? || line.end_with?(':<none>') }
      end

      def prune_dangling_images
        Open3.capture2e('docker', 'image', 'prune', '-f')
      end
    end
  end
end
