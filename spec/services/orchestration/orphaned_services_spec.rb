RSpec.describe Orchestration::OrphanedServices do
  describe '.detect' do
    def mock_container(name, stoppable: true, image: nil)
      instance_double(
        Orchestration::Container,
        service_name: name,
        stoppable?: stoppable,
        image: image,
      )
    end

    def mock_compose_with(service_names)
      services = service_names.map do |name|
        instance_double(Compose::Service, name:)
      end
      collection = mock_service_collection(services)
      allow(collection).to receive(:to_set) { service_names.to_set }
      allow(Compose).to receive(:load).and_return(
        instance_double(Compose::File, services: collection),
      )
    end

    context 'when all running containers are in compose.yaml' do
      before do
        mock_compose_with(%w[dashboard influxdb redis])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('dashboard'),
            mock_container('influxdb'),
            mock_container('redis'),
          ],
        )
      end

      it 'returns empty array' do
        expect(described_class.detect).to eq([])
      end
    end

    context 'when a managed service runs but is not in compose.yaml' do
      let(:orphaned) { mock_container('forecast-collector') }

      before do
        mock_compose_with(%w[dashboard influxdb redis])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('dashboard'),
            mock_container('influxdb'),
            orphaned,
          ],
        )
      end

      it 'returns the orphaned container' do
        expect(described_class.detect).to eq([orphaned])
      end
    end

    context 'when an unmanaged service runs but is not in compose.yaml' do
      before do
        mock_compose_with(%w[dashboard])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('dashboard'),
            mock_container('my-custom-service', image: 'nginx:latest'),
          ],
        )
      end

      it 'ignores non-managed services' do
        expect(described_class.detect).to eq([])
      end
    end

    # After importing a stack that ran one collector per device, HELIOS emits a
    # single shelly-collector. The old per-device containers keep running under
    # their original names (shelly-collector-fridge, ...), which match no
    # canonical name — only the HELIOS-managed image still identifies them.
    context 'when consolidated per-device collectors keep running' do
      let(:fridge) do
        mock_container(
          'shelly-collector-fridge',
          image: 'ghcr.io/solectrus/shelly-collector:latest',
        )
      end
      let(:dishwasher) do
        mock_container(
          'shelly-collector-dishwasher',
          image: 'ghcr.io/solectrus/shelly-collector:latest',
        )
      end

      before do
        mock_compose_with(%w[dashboard shelly-collector])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container(
              'shelly-collector',
              image: 'ghcr.io/solectrus/shelly-collector:latest',
            ),
            fridge,
            dishwasher,
          ],
        )
      end

      it 'detects the per-device containers by image but not the consolidated one' do
        expect(described_class.detect).to contain_exactly(fridge, dishwasher)
      end
    end

    context 'when an orphaned managed container is not stoppable' do
      before do
        mock_compose_with(%w[dashboard])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('dashboard'),
            mock_container('forecast-collector', stoppable: false),
          ],
        )
      end

      it 'excludes non-stoppable containers' do
        expect(described_class.detect).to eq([])
      end
    end

    context 'when container has blank service_name' do
      before do
        mock_compose_with(%w[dashboard])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('dashboard'),
            mock_container(nil),
          ],
        )
      end

      it 'ignores containers without service name' do
        expect(described_class.detect).to eq([])
      end
    end
  end
end
