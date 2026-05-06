RSpec.describe Import::ConfigurationImporter::ShellyExtractor do
  subject(:extractor) { described_class.new(reader, {}) }

  let(:reader) do
    instance_double(Import::StackReader,
                    services: { 'shelly-collector' => service },
                    service: service,
                    raw_compose: { 'services' => { 'shelly-collector' => { 'environment' => raw_env } } })
  end
  let(:service) { { 'image' => 'ghcr.io/solectrus/shelly-collector:develop', 'environment' => env } }
  let(:raw_env) { env.map { |k, v| "#{k}=#{v}" } }

  describe '#raw_devices' do
    context 'with a local-mode stack' do
      let(:env) do
        {
          'SHELLY_HOST' => '${SHELLY_HOST_HEATPUMP},${SHELLY_HOST_FRIDGE}',
          'INFLUX_MEASUREMENT' => 'Heatpump,Fridge',
        }
      end

      it 'extracts host-keyed devices and derives names from the SHELLY_HOST_<NAME> placeholders' do
        expect(extractor.raw_devices).to eq(
          [
            { 'name' => 'heatpump', 'host' => '${SHELLY_HOST_HEATPUMP}', 'measurement' => 'Heatpump' },
            { 'name' => 'fridge', 'host' => '${SHELLY_HOST_FRIDGE}', 'measurement' => 'Fridge' },
          ],
        )
      end
    end

    context 'with a cloud-mode stack' do
      let(:env) do
        {
          'SHELLY_CLOUD_SERVER' => 'https://shelly-42-eu.shelly.cloud',
          'SHELLY_AUTH_KEY' => 'cloud-key',
          'SHELLY_DEVICE_ID' => 'aabbccdd0001,aabbccdd0002',
          'INFLUX_MEASUREMENT' => 'Heatpump,Fridge',
        }
      end

      it 'extracts device_id-keyed devices with placeholder names' do
        expect(extractor.raw_devices).to eq(
          [
            { 'name' => 'device1', 'device_id' => 'aabbccdd0001', 'measurement' => 'Heatpump' },
            { 'name' => 'device2', 'device_id' => 'aabbccdd0002', 'measurement' => 'Fridge' },
          ],
        )
      end

      it 'reports cloud as the connection type in the section data' do
        expect(extractor.section_data).to include('connection' => 'cloud',
                                                  'cloud_server' => 'https://shelly-42-eu.shelly.cloud',
                                                  'auth_key' => 'cloud-key')
      end
    end

    context 'with mixed per-device passwords' do
      let(:env) do
        {
          'SHELLY_HOST' => 'shelly-a.local,shelly-b.local',
          'INFLUX_MEASUREMENT' => 'A,B',
          'SHELLY_PASSWORD' => 'pa,pb',
        }
      end

      it 'attributes the passwords back to their devices' do
        expect(extractor.raw_devices.map { |d| d.slice('host', 'password') }).to eq(
          [
            { 'host' => 'shelly-a.local', 'password' => 'pa' },
            { 'host' => 'shelly-b.local', 'password' => 'pb' },
          ],
        )
      end

      it 'leaves the shared_password global key empty when values differ' do
        expect(extractor.shared_password).to be_nil
      end
    end

    context 'with a single shared password' do
      let(:env) do
        {
          'SHELLY_HOST' => 'shelly-a.local,shelly-b.local',
          'INFLUX_MEASUREMENT' => 'A,B',
          'SHELLY_PASSWORD' => 'shared',
        }
      end

      it 'keeps the password on the global section, not on the devices' do
        expect(extractor.raw_devices.pluck('password')).to eq([nil, nil])
        expect(extractor.shared_password).to eq('shared')
      end
    end

    context 'with per-device invert_power flags' do
      let(:env) do
        {
          'SHELLY_HOST' => 'shelly-a.local,shelly-b.local,shelly-c.local',
          'INFLUX_MEASUREMENT' => 'A,B,C',
          'SHELLY_INVERT_POWER' => 'true,,true',
        }
      end

      it 'sets invert_power only on the matching devices' do
        flags = extractor.raw_devices.pluck('invert_power')
        expect(flags).to eq([true, nil, true])
      end
    end
  end
end
