require 'rails_helper'

RSpec.describe ComposeRunner do
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
          ComposeRunner::CommandError,
          /not configured/,
        )
      end
    end

    context 'when stack path does not exist' do
      before { FileUtils.rm_rf(stack_path) }

      it 'raises CommandError' do
        expect { described_class.up }.to raise_error(
          ComposeRunner::CommandError,
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
        expect(result).to be_a(ComposeRunner::CommandResult)
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

  describe '.restart' do
    before { skip_without_docker }

    context 'with running containers' do
      before do
        File.write(File.join(stack_path, 'compose.yaml'), <<~YAML)
          name: helios-test
          services:
            test:
              image: alpine:latest
              command: sleep 60
        YAML
        system(
          'docker compose up -d',
          chdir: stack_path,
          out: File::NULL,
          err: File::NULL,
        )
      end

      after do
        system(
          'docker compose down -v',
          chdir: stack_path,
          out: File::NULL,
          err: File::NULL,
        )
      end

      it 'restarts all services' do
        result = described_class.restart
        expect(result.success?).to be true
      end

      it 'restarts specific service' do
        result = described_class.restart('test')
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

  describe ComposeRunner::CommandResult do
    let(:result) do
      described_class.new(output: 'Container started', exit_status: 0)
    end

    describe '#success?' do
      it 'returns true when exit status is 0' do
        expect(result.success?).to be true
      end

      it 'returns false when exit status is non-zero' do
        failed_result = described_class.new(output: 'error', exit_status: 1)
        expect(failed_result.success?).to be false
      end
    end

    describe '#output' do
      it 'returns the command output' do
        expect(result.output).to eq('Container started')
      end
    end

    describe '#to_s' do
      it 'returns the output' do
        expect(result.to_s).to eq('Container started')
      end
    end
  end

  describe ComposeRunner::CommandError do
    let(:error) do
      described_class.new(
        'Command failed',
        stdout: 'out',
        stderr: 'err',
        exit_status: 1,
      )
    end

    it 'includes stdout' do
      expect(error.stdout).to eq('out')
    end

    it 'includes stderr' do
      expect(error.stderr).to eq('err')
    end

    it 'includes exit status' do
      expect(error.exit_status).to eq(1)
    end
  end
end
