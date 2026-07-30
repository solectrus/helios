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

    context 'with the default fixture' do
      # `build` runs SystemInfo.collect (shells out to df/free/uptime/…) and
      # zips the archive. These read-only assertions all share the same input,
      # so we build the bundle once with aggregate_failures.
      before { allow(SupportBundle::ContainerLogs).to receive(:collect).and_return({}) }

      it 'produces a bundle with the expected entries and content', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = entries

        expect(result.keys).to contain_exactly(
          'compose.yaml',
          '.env',
          'config.yaml',
          'compose.yaml.bak',
          '.env.bak',
          'system-info.txt',
        )

        expect(result['system-info.txt']).to include('=== HELIOS ===')
        expect(result['system-info.txt']).to include('=== Docker Engine ===')

        os_section = result['system-info.txt'][/=== Operating System ===\n.*?(?=\n===|\z)/m]
        expect(os_section).to include('Operating system')
        expect(os_section).to include('Kernel')
        expect(os_section).to include('Architecture')
        expect(os_section).not_to include('uname')

        containers_section = result['system-info.txt'][/=== Docker Containers ===\n.*?(?=\n===|\z)/m]
        expect(containers_section).to be_present
        # Either a table header (when containers exist) or the empty-state note.
        expect(containers_section).to match(/(NAME\s+STATE\s+STATUS\s+IMAGE|No containers found)/)

        # Every secret becomes a fixed 5-letter dummy; the exact letter
        # depends on the order the registry first sees each value.
        expect(result['.env']).to match(%r{\ASENEC_PASSWORD=[A-Z]{5}\nTZ=Europe/Berlin\n\z})
        expect(result['.env.bak']).to match(/\ASENEC_PASSWORD=[A-Z]{5}\n\z/)

        parsed = YAML.safe_load(result['config.yaml'])
        expect(parsed['senec']['password']).to match(/\A[A-Z]{5}\z/)
        expect(parsed['system']['admin_password']).to match(/\A[A-Z]{5}\z/)
        # `secret` appears in both .env and config.yaml → same mask in both.
        env_mask = result['.env'][/SENEC_PASSWORD=([A-Z]+)/, 1]
        expect(parsed['senec']['password']).to eq(env_mask)
      end
    end

    it 'includes per-container log files under logs/' do
      allow(SupportBundle::ContainerLogs).to receive(:collect).and_return(
        'logs/dashboard.log' => "2026-04-23T10:00:00Z booting\n",
        'logs/postgresql.log' => "2026-04-23T10:00:00Z ready\n",
      )

      expect(entries['logs/dashboard.log']).to eq("2026-04-23T10:00:00Z booting\n")
      expect(entries['logs/postgresql.log']).to eq("2026-04-23T10:00:00Z ready\n")
    end

    it 'scrubs coordinates and secrets from container logs' do
      File.write(
        File.join(data_path, '.env'),
        "FORECAST_LATITUDE=52.51627\nFORECAST_LONGITUDE=13.37774\nINFLUX_TOKEN=example-influx-token\n",
      )
      allow(SupportBundle::ContainerLogs).to receive(:collect).and_return(
        'logs/forecast-collector.log' =>
          "fetching https://api.forecast.solar/estimate/52.51627/13.37774/29\n" \
          "Authorization=Token example-influx-token\n",
      )

      log = entries['logs/forecast-collector.log']
      expect(log).not_to include('52.51627')
      expect(log).not_to include('13.37774')
      expect(log).not_to include('example-influx-token')
      expect(log).to include('forecast.solar/estimate/52.00000/13.00000/29')
      expect(log).to match(/Authorization=Token [A-Z]{5}/)
    end

    it 'builds a bundle from files that are not UTF-8' do
      File.binwrite(File.join(data_path, '.env'), "# Sch\xF6nes Wetter\nSENEC_PASSWORD=secret\n")
      allow(SupportBundle::ContainerLogs).to receive(:collect).and_return({})

      # Zip entries come back tagged BINARY; the bytes themselves are UTF-8.
      env = entries['.env'].force_encoding(Encoding::UTF_8)
      expect(env).to match(/\A# Schönes Wetter\nSENEC_PASSWORD=[A-Z]{5}\n\z/)
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
