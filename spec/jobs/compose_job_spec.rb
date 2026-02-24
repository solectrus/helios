RSpec.describe ComposeJob do
  before do
    allow(StackBuilder).to receive(:new)
      .and_return(instance_double(StackBuilder, write!: nil))
  end

  after do
    Compose::ServiceStore.clear_all
  end

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

      it 'clears stored error for the started service only' do
        Compose::ServiceStore.set('redis', 'old error')
        Compose::ServiceStore.set('influxdb', 'other error')

        described_class.perform_now(:start, 'redis')

        expect(Compose::ServiceStore.get('redis')).to be_nil
        expect(Compose::ServiceStore.get('influxdb')).to eq('other error')
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
        allow(services_collection).to receive(:each).and_yield(compose_service)
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

      it 'stores error in ServiceStore' do
        described_class.perform_now(:start, 'broken-service')

        expect(Compose::ServiceStore.get('broken-service')).to eq('Error: manifest unknown')
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
      allow(services_collection).to receive(:each).and_yield(compose_service)
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
    let(:requested_service) { instance_double(Compose::Service, name: 'dashboard', depends_on: {}) }
    let(:affected_service) { instance_double(Compose::Service, name: 'influxdb', depends_on: {}) }
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
        allow(services_collection).to receive(:each)
          .and_yield(affected_service)
          .and_yield(requested_service)
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

      it 'stores error for affected service in ServiceStore' do
        perform_with_error(
          'Error response from daemon: Conflict. The container name "/solectrus-influxdb-1" is already in use',
        )

        expect(Compose::ServiceStore.get('influxdb')).to include('already in use')
      end
    end

    context 'when error does not contain container name' do
      before do
        allow(services_collection).to receive(:find).with('dashboard').and_return(requested_service)
        allow(services_collection).to receive(:each).and_yield(requested_service)
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

  describe 'batch error with dependencies' do
    let(:influxdb_service) do
      instance_double(
        Compose::Service,
        name: 'influxdb', helios?: false, image: 'influxdb:2',
        depends_on: {}, display_name: 'InfluxDB'
      )
    end
    let(:dashboard_service) do
      instance_double(
        Compose::Service,
        name: 'dashboard', helios?: false, image: 'solectrus:latest',
        depends_on: { 'influxdb' => { 'condition' => 'service_healthy' } }
      )
    end
    let(:redis_service) do
      instance_double(
        Compose::Service,
        name: 'redis', helios?: false, image: 'redis:7', depends_on: {},
      )
    end
    let(:services_collection) { instance_double(Compose::ServiceCollection) }
    let(:compose_file) { instance_double(Compose::File, services: services_collection) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(ApplicationController).to receive(:render).and_return('<div>error</div>')
      allow(DockerHost::Container).to receive(:find).and_return(nil)
      allow(Compose).to receive(:load).and_return(compose_file)
      allow(services_collection).to receive(:find).with('influxdb').and_return(influxdb_service)
      allow(services_collection).to receive(:find).with('dashboard').and_return(dashboard_service)
      allow(services_collection).to receive(:find).with('redis').and_return(redis_service)
      allow(services_collection).to receive(:each)
        .and_yield(influxdb_service)
        .and_yield(dashboard_service)
        .and_yield(redis_service)
      allow(services_collection).to receive(:reject)
        .and_return([influxdb_service, dashboard_service, redis_service])
    end

    def perform_batch_with_error(stdout_message)
      error = Compose::Runner::CommandError.new(
        'Command failed',
        stdout: stdout_message,
        stderr: '',
        exit_status: 1,
      )
      allow(Compose::Runner).to receive(:up).and_raise(error)
      described_class.perform_now(:up)
    end

    it 'stores error for affected service' do
      perform_batch_with_error(
        'Error: container /solectrus-influxdb-1 port is already allocated',
      )

      expect(Compose::ServiceStore.get('influxdb')).to include('port is already allocated')
    end

    it 'stores dependency error for services that depend on the failed one' do
      perform_batch_with_error(
        'Error: container /solectrus-influxdb-1 port is already allocated',
      )

      expect(Compose::ServiceStore.get('dashboard')).to eq('Blocked: InfluxDB failed to start')
    end

    it 'does not store error for unrelated services' do
      perform_batch_with_error(
        'Error: container /solectrus-influxdb-1 port is already allocated',
      )

      expect(Compose::ServiceStore.get('redis')).to be_nil
    end

    it 'broadcasts dependency error to dependent services' do
      perform_batch_with_error(
        'Error: container /solectrus-influxdb-1 port is already allocated',
      )

      expect(ApplicationController).to have_received(:render).with(
        an_object_having_attributes(
          class: ServiceRow::Component,
          error_message: 'Blocked: InfluxDB failed to start',
        ),
        { layout: false },
      )
    end
  end
end
