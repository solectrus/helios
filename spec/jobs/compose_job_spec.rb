RSpec.describe ComposeJob do
  describe '#perform' do
    context 'when command succeeds' do
      before do
        allow(Compose::Runner).to receive(:start).and_return(
          Compose::CommandResult.new(output: 'OK', exit_status: 0),
        )
      end

      it 'executes start command' do
        described_class.perform_now(:start, 'redis')

        expect(Compose::Runner).to have_received(:start).with('redis')
      end
    end

    context 'when command fails' do
      let(:error) do
        Compose::Runner::CommandError.new(
          'Command failed',
          stdout: "Pulling image...\nError: manifest unknown",
          stderr: '',
          exit_status: 1,
        )
      end

      let(:compose_service) { instance_double(Compose::Service, name: 'broken-service') }
      let(:services_collection) { instance_double(Compose::ServiceCollection) }
      let(:compose_file) { instance_double(Compose::File, services: services_collection) }

      before do
        allow(Compose::Runner).to receive(:start).and_raise(error)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        allow(ApplicationController).to receive(:render).and_return('<div>html</div>')
        allow(DockerHost::Container).to receive(:find).and_return(nil)
        allow(Compose).to receive(:load).and_return(compose_file)
        allow(services_collection).to receive(:find).and_return(compose_service)
      end

      it 'broadcasts service status update' do
        described_class.perform_now(:start, 'broken-service')

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          'services',
          target: 'service-broken-service',
          html: '<div>html</div>',
        )
      end

      it 'renders service row component with last line as error message' do
        described_class.perform_now(:start, 'broken-service')

        expect(ApplicationController).to have_received(:render).with(
          an_object_having_attributes(
            class: ServiceRow::Component,
            error_message: 'Error: manifest unknown',
            pending: false,
          ),
          { layout: false },
        )
      end
    end
  end

  describe 'error message extraction' do
    let(:compose_service) { instance_double(Compose::Service, name: 'test-service') }
    let(:services_collection) { instance_double(Compose::ServiceCollection) }
    let(:compose_file) { instance_double(Compose::File, services: services_collection) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(DockerHost::Container).to receive(:find).and_return(nil)
      allow(Compose).to receive(:load).and_return(compose_file)
      allow(services_collection).to receive(:find).and_return(compose_service)
    end

    def perform_with_error(stdout_message)
      error = Compose::Runner::CommandError.new(
        'Command failed',
        stdout: stdout_message,
        stderr: '',
        exit_status: 1,
      )
      allow(Compose::Runner).to receive(:start).and_raise(error)
      allow(ApplicationController).to receive(:render).and_return('<div>error</div>')

      described_class.perform_now(:start, 'test-service')
    end

    it 'uses last line of output as error message' do
      perform_with_error("Pulling image...\nError: manifest unknown")

      expect(ApplicationController).to have_received(:render)
        .with(an_object_having_attributes(error_message: 'Error: manifest unknown'), { layout: false })
    end

    it 'strips whitespace from error message' do
      perform_with_error("line 1\n  some error with spaces  \n")

      expect(ApplicationController).to have_received(:render)
        .with(an_object_having_attributes(error_message: 'some error with spaces'), { layout: false })
    end

    it 'returns Unknown error for empty output' do
      perform_with_error('')

      expect(ApplicationController).to have_received(:render)
        .with(an_object_having_attributes(error_message: 'Unknown error'), { layout: false })
    end
  end

  describe 'affected service extraction' do
    let(:requested_service) { instance_double(Compose::Service, name: 'dashboard') }
    let(:affected_service) { instance_double(Compose::Service, name: 'influxdb') }
    let(:services_collection) { instance_double(Compose::ServiceCollection) }
    let(:compose_file) { instance_double(Compose::File, services: services_collection) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(DockerHost::Container).to receive(:find).and_return(nil)
      allow(Compose).to receive(:load).and_return(compose_file)
      allow(ApplicationController).to receive(:render).and_return('<div>error</div>')
    end

    def perform_with_error(stdout_message)
      error = Compose::Runner::CommandError.new(
        'Command failed',
        stdout: stdout_message,
        stderr: '',
        exit_status: 1,
      )
      allow(Compose::Runner).to receive(:start).and_raise(error)
      described_class.perform_now(:start, 'dashboard')
    end

    context 'when error contains container name from different service' do
      before do
        allow(services_collection).to receive(:find).with('influxdb').and_return(affected_service)
        allow(services_collection).to receive(:find).with('dashboard').and_return(requested_service)
      end

      it 'broadcasts to the affected service instead of requested service' do
        perform_with_error(
          'Error response from daemon: Conflict. The container name "/solectrus-influxdb-1" is already in use',
        )

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          'services',
          target: 'service-influxdb',
          html: '<div>error</div>',
        )
      end
    end

    context 'when extracted service does not exist in compose file' do
      before do
        allow(services_collection).to receive(:find).with('unknown').and_return(nil)
        allow(services_collection).to receive(:find).with('dashboard').and_return(requested_service)
      end

      it 'falls back to the requested service' do
        perform_with_error(
          'Error response from daemon: Conflict. The container name "/project-unknown-1" is already in use',
        )

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          'services',
          target: 'service-dashboard',
          html: '<div>error</div>',
        )
      end
    end

    context 'when error does not contain container name' do
      before do
        allow(services_collection).to receive(:find).with('dashboard').and_return(requested_service)
      end

      it 'uses the requested service' do
        perform_with_error('Some generic error without container name')

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          'services',
          target: 'service-dashboard',
          html: '<div>error</div>',
        )
      end
    end
  end
end
