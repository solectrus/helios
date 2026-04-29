RSpec.describe Orchestration::Runner do
  let(:data_path) { Rails.root.join('tmp/stack').to_s }

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

      after do
        # Clean up containers
        system(
          'docker compose down -v',
          chdir: data_path,
          out: File::NULL,
          err: File::NULL,
        )
      end

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
        system(
          'docker compose up -d',
          chdir: data_path,
          out: File::NULL,
          err: File::NULL,
        )
        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: helios-test
          services:
            new:
              image: alpine:latest
              command: sleep 30
        YAML
      end

      after do
        system(
          'docker compose down -v',
          chdir: data_path,
          out: File::NULL,
          err: File::NULL,
        )
      end

      it 'removes orphaned containers from the previous service definition' do
        described_class.up

        format = '{{.Label "com.docker.compose.service"}}'
        running = `docker ps --filter label=com.docker.compose.project=helios-test --format '#{format}'`
        expect(running.split("\n")).to contain_exactly('new')
      end
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
        system(
          'docker compose up -d',
          chdir: data_path,
          out: File::NULL,
          err: File::NULL,
        )
      end

      it 'stops and removes containers' do
        result = described_class.down
        expect(result.success?).to be true
      end
    end
  end

  describe '.self_recreate' do
    it 'runs compose up + image prune in the helper container' do
      File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
        name: solectrus
        services:
          helios:
            image: ghcr.io/solectrus/helios:develop
      YAML
      allow(described_class).to receive(:host_data_path).and_return('/opt/solectrus')
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture2e).and_return(['', status])

      described_class.self_recreate

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '--rm', '-d',
        '--entrypoint', 'sh',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', '/opt/solectrus:/opt/solectrus',
        'ghcr.io/solectrus/helios:develop',
        '-c', a_string_matching(/--force-recreate helios && docker image prune -f\z/)
      )
    end
  end

  describe '.recreate' do
    before { skip_without_docker }

    context 'when the user changes a service tag' do
      let(:project) { 'helios-recreate-test' }

      before do
        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: #{project}
          services:
            test:
              image: alpine:3.18
              command: sleep 30
        YAML
        described_class.up

        File.write(File.join(data_path, 'compose.yaml'), <<~YAML)
          name: #{project}
          services:
            test:
              image: alpine:3.19
              command: sleep 30
        YAML
      end

      after do
        system(
          'docker compose down -v',
          chdir: data_path,
          out: File::NULL,
          err: File::NULL,
        )
        system('docker', 'image', 'rm', 'alpine:3.19', out: File::NULL, err: File::NULL)
      end

      it 'removes the previously deployed image' do
        previous = instance_double(Orchestration::Container, image: 'alpine:3.18')
        allow(Orchestration::Container).to receive(:find).with('test').and_return(previous)

        expect(image_exists?('alpine:3.18')).to be(true)

        described_class.recreate('test')

        expect(image_exists?('alpine:3.18')).to be(false)
        expect(image_exists?('alpine:3.19')).to be(true)
      end
    end

    def image_exists?(image)
      system('docker', 'image', 'inspect', image, out: File::NULL, err: File::NULL)
    end
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
end
