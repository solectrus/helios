RSpec.describe StartupCheck do
  describe '.run' do
    context 'when all checks pass' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(match(%r{/(compose|docker-compose)\.(yaml|yml)$})).and_return(true)
        allow(File).to receive(:exist?).with(match(/\.env$/)).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_return({ 'name' => Orchestration::PROJECT_NAME })
      end

      it 'returns an empty array' do
        expect(described_class.run).to be_empty
      end
    end

    context 'when data path does not exist' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(false)
      end

      it 'reports data path missing' do
        failures = described_class.run
        expect(failures.map(&:name)).to include('Data path')
      end

      it 'skips compose and env checks' do
        failures = described_class.run
        names = failures.map(&:name)

        expect(names).not_to include('Compose file')
        expect(names).not_to include('Environment file')
      end
    end

    context 'when compose file is missing' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(match(%r{/(compose|docker-compose)\.(yaml|yml)$})).and_return(false)
        allow(File).to receive(:exist?).with(match(/\.env$/)).and_return(true)
      end

      it 'reports compose file missing' do
        failures = described_class.run
        expect(failures.map(&:name)).to include('Compose file')
      end
    end

    context 'when .env file is missing' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(match(%r{/(compose|docker-compose)\.(yaml|yml)$})).and_return(true)
        allow(File).to receive(:exist?).with(match(/\.env$/)).and_return(false)
        allow(YAML).to receive(:safe_load_file).and_return({ 'name' => Orchestration::PROJECT_NAME })
      end

      it 'reports env file missing' do
        failures = described_class.run
        expect(failures.map(&:name)).to include('Environment file')
      end
    end

    context 'when data path is not writable' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(Rails.configuration.data_path).and_return(false)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(match(%r{/(compose|docker-compose)\.(yaml|yml)$})).and_return(true)
        allow(File).to receive(:exist?).with(match(/\.env$/)).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_return({ 'name' => Orchestration::PROJECT_NAME })
      end

      it 'reports data path not writable' do
        failures = described_class.run
        expect(failures.map(&:name)).to include('Data path writable')
      end
    end

    context 'when compose file has the wrong project name' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(match(%r{/(compose|docker-compose)\.(yaml|yml)$})).and_return(true)
        allow(File).to receive(:exist?).with(match(/\.env$/)).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_return({ 'name' => 'wrong' })
      end

      it 'reports compose project name mismatch' do
        failures = described_class.run
        failure = failures.find { |c| c.name == 'Compose project name' }
        expect(failure).not_to be_nil
        expect(failure.message).to include('solectrus')
      end
    end

    context 'when compose file has no project name' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(Rails.configuration.data_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(match(%r{/(compose|docker-compose)\.(yaml|yml)$})).and_return(true)
        allow(File).to receive(:exist?).with(match(/\.env$/)).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_return({ 'services' => {} })
      end

      it 'reports compose project name missing' do
        failures = described_class.run
        expect(failures.map(&:name)).to include('Compose project name')
      end
    end

    it 'skips Docker checks outside production' do
      failures = described_class.run
      names = failures.map(&:name)

      expect(names).not_to include('Docker socket')
      expect(names).not_to include('Docker connection')
    end
  end

  describe 'Docker checks (unit level)' do
    before do
      allow(Orchestration::Connection).to receive(:configure!)
    end

    describe 'when Docker socket is missing' do
      before do
        allow(File).to receive(:exist?).and_call_original
        Orchestration::Connection::SOCKET_PATHS.each do |path|
          allow(File).to receive(:exist?).with(path).and_return(false)
        end
      end

      it 'reports Docker socket missing' do
        # Call the private method directly to test in isolation
        result = described_class.send(:check_docker_socket)
        expect(result.name).to eq('Docker socket')
      end

      it 'skips Docker connection check when no socket' do
        result = described_class.send(:check_docker_connection)
        expect(result).to be_nil
      end
    end

    describe 'when Docker ping fails' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(Orchestration::Connection::SOCKET_PATHS.first).and_return(true)
        allow(Docker).to receive(:ping).and_raise(Excon::Error::Socket.new(StandardError.new('connection refused')))
      end

      it 'reports Docker connection failed' do
        result = described_class.send(:check_docker_connection)
        expect(result.name).to eq('Docker connection')
        expect(result.message).to include('connection refused')
      end
    end

    describe 'when Docker is connected' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(Orchestration::Connection::SOCKET_PATHS.first).and_return(true)
        allow(Docker).to receive(:ping).and_return('OK')
      end

      it 'returns nil' do
        result = described_class.send(:check_docker_connection)
        expect(result).to be_nil
      end
    end

    describe 'check_docker_version' do
      it 'returns nil when the engine meets the minimum version' do
        allow(Orchestration::Connection).to receive(:engine_version).and_return(Gem::Version.new('24.0.2'))

        expect(described_class.send(:check_docker_version)).to be_nil
      end

      it 'reports a failure when the engine is too old' do
        allow(Orchestration::Connection).to receive(:engine_version).and_return(Gem::Version.new('20.10.24'))

        result = described_class.send(:check_docker_version)
        expect(result.name).to eq('Docker version')
        expect(result.message).to include('20.10.24', '24.0')
      end

      it 'returns nil when the engine version is unknown' do
        allow(Orchestration::Connection).to receive(:engine_version).and_return(nil)

        expect(described_class.send(:check_docker_version)).to be_nil
      end
    end
  end
end
