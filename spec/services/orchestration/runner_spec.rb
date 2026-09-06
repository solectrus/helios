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

  describe '.up' do
    before { skip_without_docker }

    context 'with minimal compose file' do
      before { File.write(File.join(data_path, 'compose.yaml'), <<~YAML) }
        name: helios-test
        services:
          test:
            image: alpine:latest
            command: sleep 10
      YAML

      after { compose_down }

      it 'starts containers in detached mode' do
        result = described_class.up
        expect(result).to be_a(Orchestration::CommandResult)
        expect(result.success?).to be true
      end
    end

    context 'with a renamed service leaving an orphan container' do
      before do
        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: helios-test
          services:
            old:
              image: alpine:latest
              command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: helios-test
          services:
            new:
              image: alpine:latest
              command: sleep 30
        YAML
      end

      after { compose_down }

      it 'removes orphaned containers from the previous service definition' do
        described_class.up

        expect(running_services).to contain_exactly('new')
      end
    end
  end

  describe '.start' do
    before { skip_without_docker }

    # The import renames services ('db' to 'postgresql'), and until the
    # replacement is started the old container keeps running under its old
    # name. Both mount the same data directory, and two PostgreSQL clusters on
    # one directory destroy the data (discussion #5878). Compose removes the
    # leftover before it starts the replacement, so the two never run at once.
    context 'when a rename left the old container running' do
      before do
        write_compose(<<~YAML)
          db:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        write_compose(<<~YAML)
          postgresql:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
      end

      after { compose_down }

      it 'removes the old container while starting the new one' do
        described_class.start('postgresql')

        expect(running_services).to contain_exactly('postgresql', 'keeper')
      end
    end

    # A HELIOS restart during a stack start kills the `up` it is running,
    # which can leave a container behind that hangs in no network. Compose
    # builds a *running* one anew by itself, so the one it starts as it found
    # it is a container that is not running.
    context 'when an interrupted start left a container without a network' do
      before do
        sweep_for_real
        write_compose(<<~YAML)
          test:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        docker_quietly('docker compose stop test')
        docker_quietly('docker network disconnect helios-test_default helios-test-test-1')
      end

      after { compose_down }

      it 'recreates it without touching the other containers' do
        keeper_id = container_id('helios-test-keeper-1')
        expect(container_networks('helios-test-test-1')).to be_empty

        described_class.start('test')

        aggregate_failures do
          expect(container_networks('helios-test-test-1')).to eq(['helios-test_default'])
          expect(running_services).to contain_exactly('test', 'keeper')
          expect(container_id('helios-test-keeper-1')).to eq(keeper_id)
        end
      end
    end

    # The sweep leaves running containers alone: compose repairs those itself
    # once an `up` covers them, and killing one that no `up` covers would
    # leave the user with nothing at all.
    context 'when a running container lost its network' do
      before do
        sweep_for_real
        write_compose(<<~YAML)
          test:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        docker_quietly('docker network disconnect helios-test_default helios-test-keeper-1')
      end

      after { compose_down }

      it 'keeps it alive while another service starts' do
        described_class.start('test')

        expect(running_services).to include('keeper')
      end

      it 'lets compose repair it once the service itself starts' do
        described_class.start('keeper')

        expect(container_networks('helios-test-keeper-1')).to eq(['helios-test_default'])
      end
    end

    # Everything rests on a stopped container keeping its network entry. Were
    # that not so, every `up` would delete every stopped service of the stack.
    context 'when another service is merely stopped' do
      before do
        sweep_for_real
        write_compose(<<~YAML)
          test:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        docker_quietly('docker compose stop keeper')
      end

      after { compose_down }

      it 'leaves its container alone' do
        keeper_id = container_id('helios-test-keeper-1')

        described_class.start('test')

        expect(container_id('helios-test-keeper-1')).to eq(keeper_id)
      end
    end

    # The price of sweeping the whole project: a stopped container of a
    # service outside the `up` is removed and nothing brings it back, so the
    # service reads as "not created" until it is started. That beats keeping
    # a container that can never reach its dependencies.
    context 'when a stopped container of another service lost its network' do
      before do
        sweep_for_real
        write_compose(<<~YAML)
          test:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        docker_quietly('docker compose stop keeper')
        docker_quietly('docker network disconnect helios-test_default helios-test-keeper-1')
      end

      after { compose_down }

      it 'removes it and leaves it uncreated' do
        described_class.start('test')

        expect(container_id('helios-test-keeper-1')).to be_nil
      end
    end
  end

  # Without Docker the specs above are skipped, so this is what keeps the
  # sweep wired into every `up` the runner does.
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

  describe '.down' do
    before { skip_without_docker }

    context 'with running containers' do
      before do
        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: helios-test
          services:
            test:
              image: alpine:latest
              command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
      end

      it 'stops and removes containers' do
        result = described_class.down
        expect(result.success?).to be true
      end
    end
  end

  describe '.recreate' do
    before { skip_without_docker }

    context 'when the user changes a service tag' do
      let(:project) { 'helios-recreate-test' }
      # Re-tag the already-cached alpine:latest as two distinct refs so the test
      # exercises an "old → new" image transition without any registry pulls.
      let(:old_image) { 'helios-test/recreate:v1' }
      let(:new_image) { 'helios-test/recreate:v2' }

      before do
        system('docker', 'pull', '-q', 'alpine:latest', out: File::NULL, err: File::NULL)
        system('docker', 'tag', 'alpine:latest', old_image, out: File::NULL, err: File::NULL)
        system('docker', 'tag', 'alpine:latest', new_image, out: File::NULL, err: File::NULL)

        # `pull_policy: never` keeps `docker compose pull` from hitting the
        # registry — these are local-only refs of alpine:latest.
        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: #{project}
          services:
            test:
              image: #{old_image}
              pull_policy: never
              command: sleep 30
        YAML
        described_class.up

        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: #{project}
          services:
            test:
              image: #{new_image}
              pull_policy: never
              command: sleep 30
        YAML
      end

      after do
        compose_down
        system('docker', 'image', 'rm', new_image, out: File::NULL, err: File::NULL)
      end

      it 'removes the previously deployed image' do
        previous = instance_double(Orchestration::Container, image: old_image)
        allow(Orchestration::Container).to receive(:find).with('test').and_return(previous)

        expect(image_exists?(old_image)).to be(true)

        described_class.recreate('test')

        expect(image_exists?(old_image)).to be(false)
        expect(image_exists?(new_image)).to be(true)
      end
    end

    # Recreating the replacement of a renamed service is the other way its
    # container comes into being, so it clears the leftover just as #start does.
    context 'when a rename left the old container running' do
      before do
        write_compose(<<~YAML)
          db:
            image: alpine:latest
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
        docker_quietly('docker compose up -d')
        write_compose(<<~YAML)
          postgresql:
            image: alpine:latest
            pull_policy: never
            command: sleep 30
          keeper:
            image: alpine:latest
            command: sleep 30
        YAML
      end

      after { compose_down }

      it 'removes the old container while creating the new one' do
        described_class.recreate('postgresql')

        expect(running_services).to contain_exactly('postgresql', 'keeper')
      end
    end

    def image_exists?(image)
      system('docker', 'image', 'inspect', image, out: File::NULL, err: File::NULL)
    end
  end

  def write_compose(services)
    File.write(
      File.join(data_path, 'compose.yaml'),
      "name: helios-test\nservices:\n#{services.indent(2)}",
    )
  end

  def compose_down
    docker_quietly('docker compose down -v')
  end

  # spec/support/detached_containers.rb stubs the sweep out for every spec, so
  # that a real `compose up` here cannot touch the developer's own stack. The
  # examples about the sweep want it back, scoped to their own project.
  def sweep_for_real
    stub_const('Orchestration::PROJECT_NAME', 'helios-test')
    allow(Orchestration::DetachedContainers).to receive(:sweep).and_call_original
  end

  def docker_quietly(command)
    system(command, chdir: data_path, out: File::NULL, err: File::NULL)
  end

  # Names of the networks a container is connected to.
  def container_networks(name)
    Orchestration::DockerCli.inspect_container(name)&.dig('NetworkSettings', 'Networks')&.keys || []
  end

  def container_id(name)
    Orchestration::DockerCli.inspect_container(name)&.fetch('Id')
  end

  # Service names of the containers currently running for the test project.
  def running_services
    format = '{{.Label "com.docker.compose.service"}}'
    `docker ps --filter label=com.docker.compose.project=helios-test --format '#{format}'`
      .split("\n")
  end

  describe '.ps' do
    before { skip_without_docker }

    context 'with compose file' do
      before { File.write(File.join(data_path, 'compose.yaml'), <<~YAML) }
        name: helios-test
        services:
          test:
            image: alpine:latest
      YAML

      it 'lists container status' do
        result = described_class.ps
        expect(result.success?).to be true
      end
    end
  end

  describe '.config_hashes' do
    # Compose resolves the bare `environment: - KEY` form from the process
    # environment before it consults --env-file. HELIOS' own container carries
    # an ADMIN_PASSWORD frozen at creation time, which used to shadow .env: the
    # hash never moved, so a password change was invisible to the drift
    # detection and the service was never flagged for restart.
    before do
      skip_without_docker

      File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
        name: helios-test
        services:
          dashboard:
            image: alpine:latest
            environment:
            - ADMIN_PASSWORD
      YAML
    end

    around do |example|
      previous = ENV.fetch('ADMIN_PASSWORD', nil)
      example.run
    ensure
      ENV['ADMIN_PASSWORD'] = previous
    end

    def hash_for(password)
      File.write(File.join(data_path, '.env'), "ADMIN_PASSWORD=#{password}\n")
      described_class.config_hashes.fetch('dashboard')
    end

    it 'reflects a changed .env value despite a stale process environment' do
      ENV['ADMIN_PASSWORD'] = 'frozen-at-container-creation'

      expect(hash_for('first')).not_to eq(hash_for('second'))
    end

    it 'ignores the value inherited from the process environment' do
      ENV['ADMIN_PASSWORD'] = 'stale-a'
      with_stale_a = hash_for('current')

      ENV['ADMIN_PASSWORD'] = 'stale-b'
      with_stale_b = hash_for('current')

      expect(with_stale_a).to eq(with_stale_b)
    end
  end
end
