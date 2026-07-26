RSpec.describe 'Import::ConfigurationImporter watchtower interval' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
      'watchtower' => { 'image' => 'nickfedor/watchtower:latest' },
    }
  end
  let(:raw_env) { {} }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when WATCHTOWER_POLL_INTERVAL is set in .env' do
    let(:raw_env) { { 'WATCHTOWER_POLL_INTERVAL' => '3600' } }

    it 'imports the interval into the system section' do
      expect(importer.result[:system]).to include('update_interval' => '3600')
    end

    it 'does not surface the variable as unmanaged' do
      expect(importer.result[:unmanaged]).to be_nil
    end
  end

  context 'when no interval is provided' do
    it 'omits update_interval from the system section' do
      expect(importer.result[:system]).not_to have_key('update_interval')
    end
  end

  context 'when the interval is set inline on the watchtower service' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'nickfedor/watchtower:latest',
          'environment' => { 'WATCHTOWER_POLL_INTERVAL' => '28800' },
        },
      }
    end

    it 'extracts the interval from the service environment' do
      expect(importer.result[:system]).to include('update_interval' => '28800')
    end
  end

  context 'when both .env and an inline service environment provide an interval' do
    let(:raw_env) { { 'WATCHTOWER_POLL_INTERVAL' => '86400' } }
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'nickfedor/watchtower:latest',
          'environment' => { 'WATCHTOWER_POLL_INTERVAL' => '28800' },
        },
      }
    end

    it 'prefers the value from .env' do
      expect(importer.result[:system]).to include('update_interval' => '86400')
    end
  end

  context 'when the interval is encoded as a --interval command argument' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'containrrr/watchtower:latest',
          'command' => '--interval 3600 --scope solectrus --cleanup',
        },
      }
    end

    it 'extracts the interval from the command string' do
      expect(importer.result[:system]).to include('update_interval' => '3600')
    end
  end

  context 'when the command is given as an array' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'containrrr/watchtower:latest',
          'command' => ['--interval', '7200', '--scope', 'solectrus'],
        },
      }
    end

    it 'extracts the interval from the command array' do
      expect(importer.result[:system]).to include('update_interval' => '7200')
    end
  end

  context 'when both .env and command provide an interval' do
    let(:raw_env) { { 'WATCHTOWER_POLL_INTERVAL' => '86400' } }
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'nickfedor/watchtower:latest',
          'command' => '--interval 3600 --scope solectrus',
        },
      }
    end

    it 'prefers the value from .env' do
      expect(importer.result[:system]).to include('update_interval' => '86400')
    end
  end

  context 'when WATCHTOWER_SCHEDULE is set in .env' do
    let(:raw_env) { { 'WATCHTOWER_SCHEDULE' => '0 30 4 * * *' } }

    it 'imports it as a fixed daily update time' do
      expect(importer.result[:system]).to include('update_mode' => 'time', 'update_time' => '04:30')
    end

    it 'does not surface the variable as unmanaged' do
      expect(importer.result[:unmanaged]).to be_nil
    end
  end

  context 'when the schedule is set inline on the watchtower service' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'nickfedor/watchtower:latest',
          'environment' => { 'WATCHTOWER_SCHEDULE' => '0 0 2 * * *' },
        },
      }
    end

    it 'extracts the time from the service environment' do
      expect(importer.result[:system]).to include('update_mode' => 'time', 'update_time' => '02:00')
    end
  end

  context 'when the schedule is encoded as a --schedule command argument' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'containrrr/watchtower:latest',
          'command' => '--schedule "0 15 3 * * *" --scope solectrus',
        },
      }
    end

    it 'extracts the time from the command string' do
      expect(importer.result[:system]).to include('update_mode' => 'time', 'update_time' => '03:15')
    end
  end

  context 'when the schedule is given as a command array' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'watchtower' => {
          'image' => 'containrrr/watchtower:latest',
          'command' => ['--schedule', '0 0 5 * * *'],
        },
      }
    end

    it 'extracts the time from the command array' do
      expect(importer.result[:system]).to include('update_mode' => 'time', 'update_time' => '05:00')
    end
  end

  # HELIOS only renders "daily at HH:MM", so an expression it could not rebuild
  # is dropped instead of being half-managed.
  context 'when the schedule is a cron HELIOS cannot represent' do
    let(:raw_env) { { 'WATCHTOWER_SCHEDULE' => '0 0 */6 * * *' } }

    it 'keeps the stack on interval polling' do
      expect(importer.result[:system]).not_to have_key('update_mode')
      expect(importer.result[:system]).not_to have_key('update_time')
    end

    it 'does not surface the variable as unmanaged' do
      expect(importer.result[:unmanaged]).to be_nil
    end
  end
end
