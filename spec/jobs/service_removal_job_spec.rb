RSpec.describe ServiceRemovalJob do
  before do
    with_startable_config_yaml(
      '_unmanaged' => {
        'services' => {
          'dozzle' => { 'image' => 'amir20/dozzle:latest', 'ports' => ['9999:8080'] },
        },
      },
    )
    allow(Orchestration::Container).to receive(:find).with('dozzle').and_return(container)
    allow(Orchestration::Container).to receive(:invalidate_cache)
    allow(Orchestration::StackStatus).to receive(:refresh!)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
  end

  after { Orchestration::StackStatus.reset! }

  let(:container) do
    instance_double(Orchestration::Container, stoppable?: true, stop_and_remove!: nil)
  end

  describe '#perform' do
    it 'removes the service from the configuration' do
      described_class.perform_now('dozzle')

      expect(Configuration.current.unmanaged_service?('dozzle')).to be false
    end

    it 'regenerates compose.yaml without the service' do
      described_class.perform_now('dozzle')

      expect(Compose.load.services.exists?('dozzle')).to be false
    end

    it 'stops and removes the running container' do
      described_class.perform_now('dozzle')

      expect(container).to have_received(:stop_and_remove!)
    end

    it 'broadcasts the row removal' do
      described_class.perform_now('dozzle')

      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to)
        .with('services', target: 'service-dozzle')
    end

    it 'clears the pending operation' do
      Orchestration::PendingOperations.set('dozzle', :remove)

      described_class.perform_now('dozzle')

      expect(Orchestration::PendingOperations.get('dozzle')).to be_nil
    end

    context 'when the service is not unmanaged' do
      it 'does nothing and skips the broadcast' do
        described_class.perform_now('postgresql')

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_remove_to)
      end
    end

    context 'when the container is not stoppable' do
      let(:container) { instance_double(Orchestration::Container, stoppable?: false) }

      it 'still removes the service and broadcasts' do
        described_class.perform_now('dozzle')

        expect(Configuration.current.unmanaged_service?('dozzle')).to be false
        expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to)
          .with('services', target: 'service-dozzle')
      end
    end
  end
end
