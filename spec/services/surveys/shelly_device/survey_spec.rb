RSpec.describe Surveys::ShellyDevice::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    let(:all_field_names) { result['pages'].flat_map { |p| p['elements'].pluck('name') } }

    before { with_config_yaml('shelly' => { 'connection' => connection }) }

    context 'when connection is local' do
      let(:connection) { 'local' }

      it 'exposes the host identifier and hides device_id' do
        expect(all_field_names).to include('host')
        expect(all_field_names).not_to include('device_id')
      end

      it 'always offers name, measurement, invert_power and password' do
        expect(all_field_names).to include('name', 'measurement', 'invert_power', 'password')
      end
    end

    context 'when connection is cloud' do
      let(:connection) { 'cloud' }

      it 'exposes the device_id identifier and hides host' do
        expect(all_field_names).to include('device_id')
        expect(all_field_names).not_to include('host')
      end
    end
  end
end
