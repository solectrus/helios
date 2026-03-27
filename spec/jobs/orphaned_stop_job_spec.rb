RSpec.describe OrphanedStopJob do
  after do
    Orchestration::StackStatus.reset!
  end

  describe '#perform' do
    let(:container) do
      instance_double(
        Orchestration::Container,
        service_name: 'forecast-collector',
        stoppable?: true,
      )
    end

    before do
      allow(Orchestration::Container).to receive(:find)
        .with('forecast-collector')
        .and_return(container)
      allow(Orchestration::Container).to receive(:invalidate_cache)
      allow(Orchestration::StackStatus).to receive(:refresh!)
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    end

    context 'when container is stoppable' do
      before do
        allow(container).to receive(:stop_and_remove!)
      end

      it 'stops and removes the container' do
        described_class.perform_now('forecast-collector')

        expect(container).to have_received(:stop_and_remove!)
      end

      it 'broadcasts removal via Turbo Streams' do
        described_class.perform_now('forecast-collector')

        expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to)
          .with('services', target: 'service-forecast-collector')
      end

      it 'invalidates container cache' do
        described_class.perform_now('forecast-collector')

        expect(Orchestration::Container).to have_received(:invalidate_cache)
      end

      it 'refreshes stack status' do
        described_class.perform_now('forecast-collector')

        expect(Orchestration::StackStatus).to have_received(:refresh!)
      end
    end

    context 'when container is not stoppable' do
      before do
        allow(container).to receive(:stoppable?).and_return(false)
      end

      it 'does not attempt to stop the container' do
        allow(container).to receive(:stop_and_remove!)
        described_class.perform_now('forecast-collector')

        expect(container).not_to have_received(:stop_and_remove!)
      end

      it 'does not broadcast removal' do
        described_class.perform_now('forecast-collector')

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_remove_to)
      end
    end

    context 'when container is not found' do
      before do
        allow(Orchestration::Container).to receive(:find)
          .with('forecast-collector')
          .and_return(nil)
      end

      it 'does not raise an error' do
        expect { described_class.perform_now('forecast-collector') }
          .not_to raise_error
      end

      it 'does not broadcast removal' do
        described_class.perform_now('forecast-collector')

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_remove_to)
      end
    end
  end
end
