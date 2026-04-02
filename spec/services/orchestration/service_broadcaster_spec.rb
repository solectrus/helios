RSpec.describe Orchestration::ServiceBroadcaster do
  let(:service_name) { 'influxdb' }
  let(:broadcaster) { described_class.new(listener_id: 'test-listener') }

  after { Orchestration::ErrorStore.clear_all }

  describe '#broadcast' do
    before do
      stub_docker_lookup(container:)
      stub_compose_lookup(compose_service:)
      stub_broadcast_pipeline
    end

    context 'when container is running' do
      let(:container) { mock_container(running: true, status: :ok) }
      let(:compose_service) { instance_double(Compose::Service) }

      before { Orchestration::ErrorStore.set(service_name, 'old error') }

      it 'returns true' do
        expect(broadcaster.broadcast(service_name)).to be true
      end

      it 'clears the stored error' do
        broadcaster.broadcast(service_name)

        expect(Orchestration::ErrorStore.get(service_name)).to be_nil
      end
    end

    context 'when container is not running' do
      let(:container) { mock_container(running: false, status: :stopped) }
      let(:compose_service) { instance_double(Compose::Service) }

      before { Orchestration::ErrorStore.set(service_name, 'Start failed') }

      it 'preserves the stored error' do
        broadcaster.broadcast(service_name)

        expect(Orchestration::ErrorStore.get(service_name)).to eq('Start failed')
      end
    end

    context 'when container is nil' do
      let(:container) { nil }
      let(:compose_service) { instance_double(Compose::Service) }

      it 'returns true' do
        expect(broadcaster.broadcast(service_name)).to be true
      end
    end

    context 'when compose_service is not found' do
      let(:container) { mock_container(running: true, status: :ok) }
      let(:compose_service) { nil }

      it 'returns false without broadcasting' do
        expect(broadcaster.broadcast(service_name)).to be false
      end
    end

    context 'when an error occurs during Docker lookup' do
      let(:container) { nil }
      let(:compose_service) { nil }
      let(:logger) { instance_double(Logger, error: nil) }

      before do
        allow(Orchestration::Container).to receive(:find).and_raise(StandardError, 'Docker API timeout')
        allow(Orchestration::EventsListener::Logging).to receive(:logger).and_return(logger)
      end

      it 'returns false' do
        expect(broadcaster.broadcast(service_name)).to be false
      end

      it 'logs with listener_id prefix' do
        broadcaster.broadcast(service_name)

        expect(logger).to have_received(:error).with(
          '[test-listener] Broadcast error for influxdb: StandardError: Docker API timeout',
        )
      end
    end

    context 'when created is true' do
      let(:container) { mock_container(running: true, status: :ok) }
      let(:compose_service) { instance_double(Compose::Service) }

      it 'updates deployed hash for the service' do
        broadcaster.broadcast(service_name, created: true)

        expect(Orchestration::AffectedServices).to have_received(:update_deployed_hash!).with(service_name)
      end

      it 'does not invalidate config hashes' do
        broadcaster.broadcast(service_name, created: true)

        expect(Orchestration::AffectedServices).not_to have_received(:invalidate_config_hashes)
      end
    end

    context 'when created is false' do
      let(:container) { mock_container(running: true, status: :ok) }
      let(:compose_service) { instance_double(Compose::Service) }

      it 'invalidates config hashes' do
        broadcaster.broadcast(service_name)

        expect(Orchestration::AffectedServices).to have_received(:invalidate_config_hashes)
      end

      it 'does not update deployed hash' do
        broadcaster.broadcast(service_name)

        expect(Orchestration::AffectedServices).not_to have_received(:update_deployed_hash!)
      end
    end

    context 'when listener_id is nil' do
      let(:broadcaster) { described_class.new }
      let(:container) { nil }
      let(:compose_service) { nil }
      let(:logger) { instance_double(Logger, error: nil) }

      before do
        allow(Orchestration::Container).to receive(:find).and_raise(StandardError, 'fail')
        allow(Orchestration::EventsListener::Logging).to receive(:logger).and_return(logger)
      end

      it 'logs without prefix' do
        broadcaster.broadcast(service_name)

        expect(logger).to have_received(:error).with(
          'Broadcast error for influxdb: StandardError: fail',
        )
      end
    end
  end

  private

  def mock_container(running:, status:)
    instance_double(Orchestration::Container, running?: running, effective_status: status)
  end

  def stub_docker_lookup(container:)
    allow(Orchestration::Container).to receive(:invalidate_cache)
    allow(Orchestration::AffectedServices).to receive(:invalidate_config_hashes)
    allow(Orchestration::AffectedServices).to receive(:update_deployed_hash!)
    allow(Orchestration::Container).to receive(:find).and_return(container)
  end

  def stub_compose_lookup(compose_service:)
    services = instance_double(Compose::ServiceCollection, find: compose_service)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services:),
    )
  end

  def stub_broadcast_pipeline
    allow(ApplicationController).to receive(:render).and_return('<html>')
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Orchestration::StackStatus).to receive(:update)
  end
end
