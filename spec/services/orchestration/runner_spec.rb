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
