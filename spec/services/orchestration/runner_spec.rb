RSpec.describe Orchestration::Runner do
  # Unique per parallel worker so concurrent specs don't clobber each other.
  let(:data_path) { Rails.root.join("tmp/stack#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(
      data_path,
    )
    FileUtils.mkdir_p(data_path)
  end

  after { FileUtils.rm_rf(data_path) }

  describe '.data_path' do
    it 'returns the configured stack path' do
      expect(described_class.data_path).to eq(data_path)
    end
  end

  describe '#host_data_path' do
    context 'when not in production' do
      it 'returns data_path without inspecting Docker' do
        allow(Orchestration::Container).to receive(:find)

        expect(described_class.send(:host_data_path)).to eq(data_path)
        expect(Orchestration::Container).not_to have_received(:find)
      end
    end

    context 'when in production' do
      before { allow(Rails.env).to receive(:production?).and_return(true) }

      it 'returns the host-side mount source for data_path' do
        container = instance_double(Orchestration::Container)
        allow(container).to receive(:mount_source).with(data_path).and_return('/opt/solectrus')
        allow(Orchestration::Container).to receive(:find).with('helios').and_return(container)

        expect(described_class.send(:host_data_path)).to eq('/opt/solectrus')
      end

      it 'raises CommandError when the container cannot be found' do
        allow(Orchestration::Container).to receive(:find).with('helios').and_return(nil)

        expect { described_class.send(:host_data_path) }.to raise_error(
          Orchestration::Runner::CommandError,
          /Cannot resolve HELIOS host mount/,
        )
      end

      it 'raises CommandError when the mount source is missing' do
        container = instance_double(Orchestration::Container)
        allow(container).to receive(:mount_source).with(data_path).and_return(nil)
        allow(Orchestration::Container).to receive(:find).with('helios').and_return(container)

        expect { described_class.send(:host_data_path) }.to raise_error(
          Orchestration::Runner::CommandError,
          /Cannot resolve HELIOS host mount/,
        )
      end
    end
  end

  describe 'validation' do
    context 'when stack path is not set' do
      before do
        allow(Rails.configuration).to receive(:data_path).and_return(
          nil,
        )
      end

      it 'raises CommandError' do
        expect { described_class.up }.to raise_error(
          Orchestration::Runner::CommandError,
          /not configured/,
        )
      end
    end

    context 'when stack path does not exist' do
      before { FileUtils.rm_rf(data_path) }

      it 'raises CommandError' do
        expect { described_class.up }.to raise_error(
          Orchestration::Runner::CommandError,
          /does not exist/,
        )
      end
    end
  end

  describe 'compose command construction' do
    before { File.write(File.join(data_path, 'compose.yaml'), "name: x\nservices: {}\n") }

    it 'passes host_data_path as --project-directory' do
      allow(described_class).to receive(:host_data_path).and_return('/opt/solectrus')
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture2e).and_return(['', status])

      described_class.ps

      expect(Open3).to have_received(:capture2e) do |*cmd|
        project_dir = cmd[cmd.index('--project-directory') + 1]
        expect(project_dir).to eq('/opt/solectrus')
      end
    end
  end

  # The exact flags matter: they are what keeps the streams byte-clean for a
  # database dump and what stops compose from pulling in dependencies.
  describe 'the compose command line' do
    before do
      File.write(File.join(data_path, 'compose.yaml'), "name: x\nservices: {}\n")
      allow(described_class).to receive(:host_data_path).and_return('/opt/solectrus')
    end

    # Collects what the last Open3 call was given, so each example can assert
    # on the exact command line without an instance variable.
    let(:captured) { {} }

    def stub_capture2e
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture2e) do |*args|
        captured[:args] = args
        ['', status]
      end
    end

    def stub_capture3(stdout: '', stderr: '', exitstatus: 0)
      status = instance_double(Process::Status, exitstatus:)
      allow(Open3).to receive(:capture3) do |*args, **opts|
        captured[:args] = args
        captured[:opts] = opts
        [stdout, stderr, status]
      end
    end

    # Pausing freezes the container in place; only `down` tears it apart.
    it 'stops, pauses and unpauses a single service' do
      stub_capture2e

      { stop: 'down', pause: 'pause', unpause: 'unpause' }.each do |method, verb|
        described_class.public_send(method, 'dashboard')

        expect(captured[:args].last(2)).to eq([verb, 'dashboard'])
      end
    end

    # `down` names the services instead of tearing the whole project down:
    # HELIOS runs inside the stack and must not stop itself.
    it 'brings every service but its own down' do
      File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
        name: x
        services:
          dashboard:
            image: alpine:latest
          helios:
            image: alpine:latest
      YAML
      stub_capture2e

      described_class.down(remove_volumes: true)

      expect(captured[:args].last(3)).to eq(%w[down -v dashboard])
    end

    describe '.logs' do
      before { stub_capture2e }

      it 'tails a fixed number of lines' do
        described_class.logs(service: 'dashboard', tail: 50, timestamps: true)

        expect(captured[:args][captured[:args].index('logs')..]).to eq(%w[logs --timestamps --tail 50 dashboard])
      end

      # Docker ignores --until while --tail is set, so only one of them is
      # sent; without a service the whole project is followed.
      it 'drops the tail limit when an upper time bound is given' do
        described_class.logs(service: 'dashboard', tail: 50, until_timestamp: '2026-05-08T10:00:00Z')
        expect(captured[:args]).to include('--until', '2026-05-08T10:00:00Z')
        expect(captured[:args]).not_to include('--tail')

        described_class.logs(follow: true, tail: nil)
        expect(captured[:args][captured[:args].index('logs')..]).to eq(%w[logs -f])
      end
    end

    it 'streams logs from a child process and hands back its io and pid' do
      io = instance_double(IO, pid: 4242)
      allow(IO).to receive(:popen).and_return(io)

      expect(described_class.stream_logs(service: 'dashboard', tail: 10)).to eq([io, 4242])
      expect(IO).to have_received(:popen) do |_env, cmd, **|
        expect(cmd).to include('logs', '-f', '--timestamps', '--tail', '10', 'dashboard')
      end
    end

    it 'execs inside a running service without a TTY' do
      stub_capture3(stdout: "5\n", exitstatus: 0)

      expect(described_class.compose_exec('postgresql', 'psql', '-tAc', 'SELECT 1'))
        .to eq(["5\n", '', 0])
      expect(captured[:args]).to include('exec', '-T', 'postgresql', 'psql', '-tAc', 'SELECT 1')
    end

    it 'passes stdin data to an exec that asks for it' do
      stub_capture3
      described_class.compose_exec('postgresql', 'psql', stdin_data: 'SELECT 1')

      expect(captured[:opts]).to eq(stdin_data: 'SELECT 1')
    end

    # A database dump is far larger than RAM, so it moves through files
    # rather than through the process: stdout goes straight to out_path,
    # stdin comes straight from in_path, and only stderr is buffered.
    describe '.compose_exec_streaming' do
      before do
        allow(Process).to receive(:spawn) do |_env, *_cmd, **redirects|
          captured[:redirects] = redirects
          File.write(redirects[:err], "oops\n")
          4242
        end
        allow(Process).to receive(:waitpid2)
          .with(4242).and_return([4242, instance_double(Process::Status, exitstatus: 3)])
      end

      it 'redirects stdout to the given file and reports stderr with the exit code' do
        out_path = File.join(data_path, 'dump.sql')

        expect(described_class.compose_exec_streaming('postgresql', 'pg_dumpall', out_path:))
          .to eq(["oops\n", 3])
        expect(captured[:redirects][:out]).to eq(out_path)
        expect(captured[:redirects]).not_to have_key(:in)
      end

      it 'reads stdin from the given file and discards stdout when none is wanted' do
        in_path = File.join(data_path, 'restore.sql')

        described_class.compose_exec_streaming('postgresql', 'psql', in_path:)

        expect(captured[:redirects][:in]).to eq(in_path)
        expect(captured[:redirects][:out]).to eq(File::NULL)
      end
    end

    it 'runs a throwaway container without its dependencies' do
      stub_capture3(stdout: 'done')

      expect(described_class.compose_run('postgresql', '-c', 'ls', entrypoint: 'sh'))
        .to eq(['done', '', 0])
      expect(captured[:args]).to include('run', '--rm', '--no-deps', '-T', '--entrypoint', 'sh', 'postgresql')
    end
  end

  describe 'container name conflict recovery' do
    # A stale "<id>_<service>" leftover from an interrupted recreate blocks
    # `compose up` (issue #203). The runner should remove it and retry once.
    let(:stale_name) { '479446f60e32_solectrus-db-1' }
    let(:conflict_output) do
      'Error response from daemon: Conflict. The container name ' \
        "\"/#{stale_name}\" is already in use by container \"abc123\""
    end
    let(:conflict_error) do
      Orchestration::Runner::CommandError.new(
        'docker compose up failed', stdout: conflict_output, exit_status: 1
      )
    end
    let(:success) { Orchestration::CommandResult.new(output: 'done', exit_status: 0) }

    def recover = described_class.send(:run_compose_with_conflict_recovery, 'up', '-d')

    context 'when a stale container of this project blocks the command' do
      before do
        call = 0
        allow(described_class).to receive(:run_compose) do
          call += 1
          raise conflict_error if call == 1

          success
        end
        allow(Orchestration::DockerCli).to receive(:inspect_container).with(stale_name).and_return(
          'Config' => { 'Labels' => { 'com.docker.compose.project' => 'solectrus' } },
        )
        allow(Orchestration::DockerCli).to receive(:force_remove_container).and_return([true, ''])
      end

      it 'force-removes the stale container and retries successfully' do
        expect(recover).to eq(success)
        expect(Orchestration::DockerCli).to have_received(:force_remove_container).with(stale_name)
        expect(described_class).to have_received(:run_compose).twice
      end
    end

    context 'when the conflicting container does not belong to this project' do
      before do
        allow(described_class).to receive(:run_compose).and_raise(conflict_error)
        allow(Orchestration::DockerCli).to receive(:inspect_container).and_return(nil)
        allow(Orchestration::DockerCli).to receive(:force_remove_container)
      end

      it 'leaves it untouched and re-raises the original error' do
        expect { recover }.to raise_error(conflict_error)
        expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
        expect(described_class).to have_received(:run_compose).once
      end
    end

    context 'when the failure is unrelated to a name conflict' do
      before do
        allow(described_class).to receive(:run_compose).and_raise(
          Orchestration::Runner::CommandError.new(
            'boom', stdout: 'pull access denied for some/image', exit_status: 1
          ),
        )
        allow(Orchestration::DockerCli).to receive(:force_remove_container)
      end

      it 're-raises without removing any container' do
        expect { recover }.to raise_error(Orchestration::Runner::CommandError, 'boom')
        expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
      end
    end
  end

  # spec/integration/orchestration/runner_spec.rb proves the sweep against real
  # containers. This is what keeps it wired into every `up` without Docker.
  describe 'sweeping before every up' do
    before do
      allow(described_class).to receive(:run_compose_with_conflict_recovery)
      allow(described_class).to receive(:run_compose).and_return(
        Orchestration::CommandResult.new(output: '', exit_status: 0),
      )
      allow(Orchestration::ImageCleanup).to receive(:run)
      allow(Orchestration::Container).to receive(:find)
    end

    it 'sweeps before it starts a service' do
      described_class.start('dashboard')

      expect(Orchestration::DetachedContainers).to have_received(:sweep).ordered
      expect(described_class).to have_received(:run_compose_with_conflict_recovery).ordered
    end

    it 'sweeps before it brings the stack up' do
      allow(described_class).to receive(:services_except_self).and_return(%w[dashboard])

      described_class.up

      expect(Orchestration::DetachedContainers).to have_received(:sweep)
    end

    it 'sweeps before it recreates a service' do
      described_class.recreate('dashboard')

      expect(Orchestration::DetachedContainers).to have_received(:sweep)
    end

    it 'sweeps before it reconciles services' do
      described_class.reconcile('dashboard')

      expect(Orchestration::DetachedContainers).to have_received(:sweep)
    end
  end
end
