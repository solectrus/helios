RSpec.describe Compose::Runner do
  let(:stack_path) { Rails.root.join('tmp/stack').to_s }

  before do
    allow(Rails.configuration).to receive(:helios_stack_path).and_return(
      stack_path,
    )
    FileUtils.mkdir_p(stack_path)
  end

  after { FileUtils.rm_rf(stack_path) }

  describe '.stack_path' do
    it 'returns the configured stack path' do
      expect(described_class.stack_path).to eq(stack_path)
    end
  end

  describe 'validation' do
    context 'when stack path is not set' do
      before do
        allow(Rails.configuration).to receive(:helios_stack_path).and_return(
          nil,
        )
      end

      it 'raises CommandError' do
        expect { described_class.up }.to raise_error(
          Compose::Runner::CommandError,
          /not configured/,
        )
      end
    end

    context 'when stack path does not exist' do
      before { FileUtils.rm_rf(stack_path) }

      it 'raises CommandError' do
        expect { described_class.up }.to raise_error(
          Compose::Runner::CommandError,
          /does not exist/,
        )
      end
    end
  end

  describe '.up' do
    before { skip_without_docker }

    context 'with minimal compose file' do
      before { File.write(File.join(stack_path, 'compose.yaml'), <<~YAML) }
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
          chdir: stack_path,
          out: File::NULL,
          err: File::NULL,
        )
      end

      it 'starts containers in detached mode' do
        result = described_class.up
        expect(result).to be_a(Compose::CommandResult)
        expect(result.success?).to be true
      end
    end
  end

  describe '.down' do
    before { skip_without_docker }

    context 'with running containers' do
      before do
        File.write(File.join(stack_path, 'compose.yaml'), <<~YAML)
          name: helios-test
          services:
            test:
              image: alpine:latest
              command: sleep 30
        YAML
        system(
          'docker compose up -d',
          chdir: stack_path,
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

  describe '.pull' do
    before { skip_without_docker }

    context 'with compose file' do
      before { File.write(File.join(stack_path, 'compose.yaml'), <<~YAML) }
        name: helios-test
        services:
          test:
            image: alpine:latest
      YAML

      it 'pulls images' do
        result = described_class.pull
        expect(result.success?).to be true
      end

      it 'pulls specific service' do
        result = described_class.pull(service: 'test')
        expect(result.success?).to be true
      end
    end
  end

  describe '.ps' do
    before { skip_without_docker }

    context 'with compose file' do
      before { File.write(File.join(stack_path, 'compose.yaml'), <<~YAML) }
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
