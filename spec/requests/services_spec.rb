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
end
