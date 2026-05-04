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
  end
end
