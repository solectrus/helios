require 'zip'

RSpec.describe SupportBundle do
  describe '.build' do
    let(:data_path) { Dir.mktmpdir }

    before do
      allow(Rails.configuration).to receive(:data_path).and_return(data_path)
      FileUtils.mkdir_p(File.join(data_path, 'helios'))

      File.write(File.join(data_path, 'compose.yaml'), "services:\n  app:\n    image: foo\n")
      File.write(File.join(data_path, '.env'), "SENEC_PASSWORD=secret\nTZ=Europe/Berlin\n")
      File.write(
        File.join(data_path, 'helios', 'config.yaml'),
        "senec:\n  password: secret\nsystem:\n  admin_password: keepme\n",
      )
      File.write(File.join(data_path, 'compose.yaml.bak'), "old compose\n")
      File.write(File.join(data_path, '.env.bak'), "SENEC_PASSWORD=old_secret\n")
    end

    after { FileUtils.remove_entry(data_path) }

    def entries
      zip = Zip::File.open_buffer(StringIO.new(described_class.build))
      zip.to_h { |e| [e.name, e.get_input_stream.read] }
    end

    it 'contains the expected files' do
      allow(SupportBundle::ContainerLogs).to receive(:collect).and_return({})

      expect(entries.keys).to contain_exactly(
        'compose.yaml',
        '.env',
        'config.yaml',
        'compose.yaml.bak',
        '.env.bak',
        'system-info.txt',
      )
    end

    it 'includes per-container log files under logs/' do
      allow(SupportBundle::ContainerLogs).to receive(:collect).and_return(
        'logs/dashboard.log' => "2026-04-23T10:00:00Z booting\n",
        'logs/postgresql.log' => "2026-04-23T10:00:00Z ready\n",
      )

      expect(entries['logs/dashboard.log']).to eq("2026-04-23T10:00:00Z booting\n")
      expect(entries['logs/postgresql.log']).to eq("2026-04-23T10:00:00Z ready\n")
    end

    it 'includes a non-empty system-info report' do
      expect(entries['system-info.txt']).to include('=== HELIOS ===')
      expect(entries['system-info.txt']).to include('=== Docker Engine ===')
    end

    it 'reports the Docker host OS rather than the HELIOS container' do
      report = entries['system-info.txt']
      os_section = report[/=== Operating System ===\n.*?(?=\n===|\z)/m]

      expect(os_section).to include('Operating system')
      expect(os_section).to include('Kernel')
      expect(os_section).to include('Architecture')
      expect(os_section).not_to include('uname')
    end

    it 'includes a Containers section' do
      report = entries['system-info.txt']
      containers_section = report[/=== Containers ===\n.*?(?=\n===|\z)/m]

      expect(containers_section).to be_present
      # Either a table header (when containers exist) or the empty-state note.
      expect(containers_section).to match(/(NAME\s+STATE\s+STATUS\s+IMAGE|No containers found)/)
    end

    it 'anonymizes whitelisted env variables in .env' do
      expect(entries['.env']).to eq(
        "SENEC_PASSWORD=dummy_senec_password\nTZ=Europe/Berlin\n",
      )
    end

    it 'anonymizes whitelisted env variables in the backup .env' do
      expect(entries['.env.bak']).to eq("SENEC_PASSWORD=dummy_senec_password\n")
    end

    it 'anonymizes whitelisted YAML fields in config.yaml' do
      parsed = YAML.safe_load(entries['config.yaml'])

      expect(parsed['senec']['password']).to eq('dummy_password')
      expect(parsed['system']['admin_password']).to eq('dummy_admin_password')
    end

    it 'skips files that do not exist on disk' do
      File.delete(File.join(data_path, 'compose.yaml.bak'))

      expect(entries.keys).not_to include('compose.yaml.bak')
    end
  end

  describe '.filename' do
    it 'includes a timestamp and zip extension' do
      allow(Time).to receive(:current).and_return(Time.zone.local(2026, 4, 23, 10, 30, 45))

      expect(described_class.filename).to eq('helios-support-20260423-103045.zip')
    end
  end
end
