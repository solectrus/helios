require 'open3'
require 'tempfile'

module Orchestration
  class Runner
    extend Loggable

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
        result = run_compose_with_conflict_recovery(*args)
        ImageCleanup.run
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
        result = run_compose_with_conflict_recovery('up', '--no-build', '-d', service.to_s)
        ImageCleanup.run(previous_image:)
        result
      end

      def start(*services)
        args = %w[up --no-build -d]
        args.concat(services.flatten.compact)
        run_compose_with_conflict_recovery(*args)
      end

      # Reconciles the given services against the current compose in a single
      # `up`: services whose config drifted are recreated, those already
      # matching are left running, and containers from services no longer in
      # the compose file are pruned (--remove-orphans). Unlike #up the caller
      # passes exactly which services to bring in line, so a reconcile after a
      # single-service operation (e.g. a database upgrade that renamed the DB
      # service) does not spin up unrelated stopped services. No-op when empty.
      def reconcile(*services)
        names = services.flatten.compact
        return if names.empty?

        run_compose_with_conflict_recovery('up', '--no-build', '--remove-orphans', '-d', *names)
      end

      def stop(service)
        args = ['down']
        args << service
        run_compose(*args)
      end

      # Freezes a service in place instead of tearing it down: the container,
      # its logs and its state survive, Docker reports it as `paused`, and
      # #unpause brings it back in a fraction of a second. Used for the update
      # pause (see UpdatePause), where recreating the container is the very
      # thing to avoid.
      def pause(service)
        run_compose('pause', service.to_s)
      end

      # Fails when the container is not paused, so callers that cannot rule
      # that out have to check first.
      def unpause(service)
        run_compose('unpause', service.to_s)
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
        io = IO.popen(::Env.spawn_overrides, cmd, err: %i[child out])

        [io, io.pid]
      end

      # Runs a command inside a running compose service via `docker compose
      # exec`. `-T` disables TTY allocation so stdin and stdout stay
      # byte-clean — required for piping a database dump in and out.
      # Returns [stdout, stderr, exit_status].
      def compose_exec(service, *command, stdin_data: nil)
        validate_data_path!

        cmd = compose_base_command + ['exec', '-T', service.to_s, *command.map(&:to_s)]
        capture_opts = stdin_data ? { stdin_data: } : {}
        stdout, stderr, status = Open3.capture3(::Env.spawn_overrides, *cmd, **capture_opts)
        [stdout, stderr, status.exitstatus]
      end

      # Like #compose_exec, but streams stdin from a file and/or stdout to a
      # file instead of buffering them in memory — required for a database
      # dump, which can be far larger than available RAM. Pass `in_path` to
      # feed the command its stdin, `out_path` to capture its stdout; either
      # may be omitted. stderr is always captured (it stays small).
      # Returns [stderr, exit_status].
      def compose_exec_streaming(service, *command, in_path: nil, out_path: nil)
        validate_data_path!

        cmd = compose_base_command + ['exec', '-T', service.to_s, *command.map(&:to_s)]
        Tempfile.create('helios-exec-stderr') do |stderr_file|
          redirects = { err: stderr_file.path, out: out_path || ::File::NULL }
          redirects[:in] = in_path if in_path
          pid = Process.spawn(::Env.spawn_overrides, *cmd, **redirects)
          _, status = Process.waitpid2(pid)
          [::File.read(stderr_file.path), status.exitstatus]
        end
      end

      # Runs a one-off command in a throwaway container for a compose service
      # via `docker compose run`. Unlike #compose_exec the service need not be
      # running — the container is created fresh with the service's volumes,
      # the command runs, and `--rm` removes it. `--no-deps` skips
      # dependencies, `-T` keeps the streams byte-clean. `entrypoint`
      # overrides the image entrypoint (e.g. 'sh' to run a shell instead of
      # the service itself). Returns [stdout, stderr, exit_status].
      def compose_run(service, *command, entrypoint: nil)
        validate_data_path!

        args = %w[run --rm --no-deps -T]
        args.push('--entrypoint', entrypoint.to_s) if entrypoint
        cmd = compose_base_command + args + [service.to_s, *command.map(&:to_s)]
        stdout, stderr, status = Open3.capture3(::Env.spawn_overrides, *cmd)
        [stdout, stderr, status.exitstatus]
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

      # In production, data_path (e.g. /data) is container-internal; the Docker
      # daemon runs on the host and needs the real host path to resolve bind-mount
      # sources. In dev/test, data_path is already a host path.
      def host_data_path
        return data_path unless Rails.env.production?

        source = Orchestration::Container.find(SELF_SERVICE)&.mount_source(data_path)
        raise CommandError, "Cannot resolve HELIOS host mount for #{data_path}" unless source

        source
      end

      private

      # Runs a compose command and, if it fails because a container name is
      # already in use, force-removes the offending stale container(s) and
      # retries once. This recovers from a previously interrupted recreate
      # that left Docker's `<id>_<name>` leftover behind (issue #203). Only
      # containers belonging to this compose project are touched, and only
      # their (data-less) container layer — SOLECTRUS data lives in bind
      # mounts, so removing the container preserves it.
      def run_compose_with_conflict_recovery(*args)
        run_compose(*args)
      rescue CommandError => e
        names = removable_conflicting_containers(e.stdout)
        raise e if names.empty?

        names.each do |name|
          logger.warn(
            "Removing stale container #{name} blocking '#{args.first}', then retrying",
          )
          DockerCli.force_remove_container(name)
        end
        run_compose(*args)
      end

      # Container names from `… The container name "/<name>" is already in
      # use …` errors, limited to containers that actually carry this
      # compose project's label (guards against removing an unrelated
      # container that happens to share the name).
      def removable_conflicting_containers(output)
        conflicting_container_names(output).select { |name| belongs_to_project?(name) }
      end

      def conflicting_container_names(output)
        output.to_s.scan(%r{container name "/?([^"]+)" is already in use}i).flatten.uniq
      end

      def belongs_to_project?(name)
        info = DockerCli.inspect_container(name)
        labels = info&.dig('Config', 'Labels') || {}
        labels[Orchestration::COMPOSE_PROJECT_LABEL] == Orchestration::PROJECT_NAME
      end

      def run_compose(*args)
        validate_data_path!

        cmd = build_compose_command(*args)
        output, status = Open3.capture2e(::Env.spawn_overrides, *cmd)

        raise_command_error(args.first, output, status) unless status.success?

        CommandResult.new(output:, exit_status: status.exitstatus)
      end

      def compose_base_command
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
        cmd
      end

      def build_compose_command(*args)
        cmd = compose_base_command
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

      def services_except_self
        ::Compose.load.services.names - [SELF_SERVICE]
      end
    end
  end
end
