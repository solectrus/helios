RSpec.describe Orchestration::OrphanedServices do
  # `configured_image` is what the detection reads: the reference the
  # container was created with, which survives the tag moving on. `image`
  # reports whatever the container list currently names, and collapses to a
  # bare digest in exactly that case.
  def mock_container(name, stoppable: true, image: nil, configured_image: :same)
    instance_double(
      Orchestration::Container,
      service_name: name,
      stoppable?: stoppable,
      image: image,
      configured_image: configured_image == :same ? image : configured_image,
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

  describe '.detect' do
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

    # After a rename the leftover container keeps running while the tag moves
    # on to the newly pulled image, so the container list names it by bare
    # digest. Reading that instead of the configured image left a legacy `db`
    # invisible next to a managed `postgresql`, both writing to the same data
    # directory.
    context 'when a renamed service left a container the list reports by digest' do
      let(:legacy_db) do
        mock_container(
          'db',
          image: 'sha256:9b4593c6de443299b46098151fc1ec154c882339b77a56334c7ce612c8a7be6a',
          configured_image: 'postgres:15-alpine',
        )
      end

      before do
        mock_compose_with(%w[dashboard postgresql])
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('postgresql', image: 'postgres:15-alpine'),
            legacy_db,
          ],
        )
      end

      it 'reports it' do
        expect(described_class.detect).to eq([legacy_db])
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

  describe '.prune!' do
    let(:orphan) { mock_container('db', image: 'postgres:15-alpine') }

    before do
      # spec/support/orphaned_services.rb stubs this away for every other spec
      allow(described_class).to receive(:prune!).and_call_original
      with_config_yaml(
        'system' => { 'timezone' => 'Europe/Berlin' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )
      mock_compose_with(%w[dashboard postgresql])
      allow(Orchestration::Container).to receive(:all).and_return(
        [mock_container('postgresql', image: 'postgres:15-alpine'), orphan],
      )
      allow(OrphanedStopJob).to receive(:perform_later)
    end

    it 'queues the removal of an orphan' do
      described_class.prune!

      expect(OrphanedStopJob).to have_received(:perform_later).with('db')
    end

    # The job runs asynchronously, so the container is still listed on the
    # next refresh — and refresh runs on every Docker event.
    it 'queues it only once while the removal is still pending' do
      2.times { described_class.prune! }

      expect(OrphanedStopJob).to have_received(:perform_later).once
    end

    # Without this a container that reappears under the same name right after
    # a removal would be ignored for as long as the claim lasts.
    it 'queues again once the removal has finished' do
      described_class.prune!
      Orchestration::PendingOperations.clear('db')
      described_class.prune!

      expect(OrphanedStopJob).to have_received(:perform_later).twice
    end

    # Before the setup is finished compose.yaml does not describe the stack,
    # so every running container would look orphaned.
    context 'when the setup is not completed' do
      before { with_config_yaml }

      it 'queues nothing' do
        described_class.prune!

        expect(OrphanedStopJob).not_to have_received(:perform_later)
      end
    end
  end

  describe '.remove!' do
    before { allow(OrphanedStopJob).to receive(:perform_later) }

    # The Remove button and the sweep share the claim, so a click while a
    # sweep is running adds no second job for the same container.
    it 'queues the removal and holds the name' do
      expect(described_class.remove!('db')).to be(true)
      expect(described_class.remove!('db')).to be(false)
      expect(OrphanedStopJob).to have_received(:perform_later).once
    end

    # Nothing runs the job's `ensure` when the queue refuses the job, so the
    # name has to come free here or no later sweep would ever see it again.
    it 'releases the name when queueing fails' do
      allow(OrphanedStopJob).to receive(:perform_later).and_raise(
        Concurrent::RejectedExecutionError,
      )

      expect { described_class.remove!('db') }.to raise_error(Concurrent::RejectedExecutionError)

      allow(OrphanedStopJob).to receive(:perform_later)
      expect(described_class.remove!('db')).to be(true)
    end
  end
end
