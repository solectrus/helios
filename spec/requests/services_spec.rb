RSpec.describe 'Services', :with_admin_password do
  before do
    with_config_yaml(
      'system' => { 'timezone' => 'Europe/Berlin' },
      'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
    )
    login
  end

  def mock_compose_services(*names)
    services = names.map { |name| mock_service(name) }
    collection = mock_service_collection(services)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
  end

  def mock_service(name)
    instance_double(
      Compose::Service,
      name: name,
      display_name: name,
      image: "#{name}:latest",
      public_port: nil,
      helios?: name == 'helios',
    )
  end

  describe 'GET /services' do
    it 'shows services when authenticated and setup completed' do
      allow(Orchestration::Container).to receive(:all).and_return([])
      mock_compose_services

      get services_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('HELIOS')
    end

    it 'shows service skeleton with lazy loading' do
      container =
        instance_double(
          Orchestration::Container,
          service_name: 'dashboard',
          running?: true,
          status: 'running',
          health_status: nil,
          version: '1.0.0',
          public_port: 3001,
        )
      allow(Orchestration::Container).to receive(:all).and_return([container])
      mock_compose_services('dashboard')

      get services_path

      expect(response.body).to include('dashboard')
      expect(response.body).to include('loading loading-spinner') # Skeleton spinner
      expect(response.body).to include('turbo-frame')
      expect(response.body).to include('src="/services/dashboard/row"') # Lazy loading URL
    end

    it 'shows service skeletons for services without containers' do
      allow(Orchestration::Container).to receive(:all).and_return([])
      mock_compose_services('redis', 'postgresql', 'dashboard')

      get services_path

      expect(response.body).to include('redis')
      expect(response.body).to include('postgresql')
      expect(response.body).to include('dashboard')
      expect(response.body).to include('loading loading-spinner') # Skeleton spinner
    end

    context 'when setup not completed' do
      before { with_config_yaml }

      it 'shows the empty state instead of the service list' do
        get services_path

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.body).to include(I18n.t('services.index.empty_title'))
          expect(response.body).to include(sensors_path)
        end
      end
    end

    context 'when in collectors_only mode with a configured source' do
      before do
        with_config_yaml(
          'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
          'senec' => { 'version' => '4', 'host' => '10.0.0.10' },
        )
        allow(Orchestration::Container).to receive(:all).and_return([])
        mock_compose_services
      end

      it 'shows the services page even without logical sensors' do
        get services_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'DELETE /services/:id' do
    # Real ServiceCollection so #exists?/#find behave; #find returns a real
    # Compose::Service, which is what the pending ServiceRow renders.
    def stub_compose(services = {})
      allow(Compose).to receive(:load).and_return(
        instance_double(Compose::File, services: Compose::ServiceCollection.new(services)),
      )
    end

    def mock_container(name, stoppable: true)
      instance_double(
        Orchestration::Container,
        service_name: name,
        running?: stoppable,
        status: stoppable ? 'running' : 'exited',
        stoppable?: stoppable,
        image: "#{name}:latest",
      )
    end

    context 'with a managed service' do
      before do
        stub_compose('postgresql' => { 'image' => 'postgres:18-alpine' })
        allow(OrphanedStopJob).to receive(:perform_later)
      end

      it 'is forbidden' do
        delete service_path('postgresql'), as: :turbo_stream

        expect(OrphanedStopJob).not_to have_received(:perform_later)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with an orphaned container' do
      before do
        stub_compose # no matching compose service
        allow(OrphanedStopJob).to receive(:perform_later)
      end

      it 'stops and removes the orphaned container' do
        allow(Orchestration::Container).to receive(:find)
          .with('old-service').and_return(mock_container('old-service'))

        delete service_path('old-service'), as: :turbo_stream

        expect(OrphanedStopJob).to have_received(:perform_later).with('old-service')
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'redirects when the orphaned container is not stoppable' do
        allow(Orchestration::Container).to receive(:find)
          .with('old-service').and_return(mock_container('old-service', stoppable: false))

        delete service_path('old-service')

        expect(OrphanedStopJob).not_to have_received(:perform_later)
        expect(response).to redirect_to(services_path)
      end
    end
  end
end
