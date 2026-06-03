RSpec.describe 'Import::ConfigurationImporter mode detection' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  let(:stack_reader) do
    instance_double(Import::StackReader, services:)
      .tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  def svc(extra = {})
    { 'image' => 'example' }.merge(extra)
  end

  describe '#mode' do
    context 'with dashboard + exposed influxdb and no device collectors' do
      let(:services) do
        {
          'dashboard' => svc,
          'influxdb' => svc('ports' => ['8086:8086']),
          'forecast-collector' => svc, # API-based, allowed in dashboard_only
          'power-splitter' => svc,
        }
      end

      it 'is dashboard_only' do
        expect(importer.mode).to eq(ConfigSchema::MODE_DASHBOARD_ONLY)
        expect(importer).to be_dashboard_only
      end
    end

    context 'with a local device collector (senec)' do
      let(:services) do
        { 'dashboard' => svc, 'influxdb' => svc('ports' => ['8086:8086']), 'senec-collector' => svc }
      end

      it 'is full' do
        expect(importer.mode).to eq(ConfigSchema::MODE_FULL)
      end
    end

    context 'with an unexposed influxdb' do
      let(:services) { { 'dashboard' => svc, 'influxdb' => svc } }

      it 'is full' do
        expect(importer.mode).to eq(ConfigSchema::MODE_FULL)
      end
    end

    context 'with no local dashboard/influxdb but a collector' do
      let(:services) { { 'senec-collector' => svc } }

      it 'is collectors_only' do
        expect(importer.mode).to eq(ConfigSchema::MODE_COLLECTORS_ONLY)
      end
    end
  end
end
