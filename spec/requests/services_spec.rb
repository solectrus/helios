RSpec.describe 'Services', :with_admin do
  before do
    with_config_yaml(
      'system' => { 'timezone' => 'Europe/Berlin' },
      'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
    )
    login
  end

  def mock_compose_services(*names)
    services = names.map { |name| mock_service(name) }
    collection = instance_double(Compose::ServiceCollection)
    allow(collection).to receive(:each) { |&block| services.each(&block) }
    allow(collection).to receive(:sorted).and_return(services)
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
      allow(DockerHost::Container).to receive(:all).and_return([])
      mock_compose_services

      get services_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('HELIOS')
    end

    it 'shows service skeleton with lazy loading' do
      container =
        instance_double(
          DockerHost::Container,
          service_name: 'dashboard',
          running?: true,
          status: 'running',
          health_status: nil,
          version: '1.0.0',
          public_port: 3001,
        )
      allow(DockerHost::Container).to receive(:all).and_return([container])
      mock_compose_services('dashboard')

      get services_path

      expect(response.body).to include('dashboard')
      expect(response.body).to include('loading loading-spinner') # Skeleton spinner
      expect(response.body).to include('turbo-frame')
      expect(response.body).to include('src="/services/dashboard/row"') # Lazy loading URL
    end

    it 'shows service skeletons for services without containers' do
      allow(DockerHost::Container).to receive(:all).and_return([])
      mock_compose_services('redis', 'postgresql', 'dashboard')

      get services_path

      expect(response.body).to include('redis')
      expect(response.body).to include('postgresql')
      expect(response.body).to include('dashboard')
      expect(response.body).to include('loading loading-spinner') # Skeleton spinner
    end

    context 'when setup not completed' do
      before { with_config_yaml }

      it 'redirects to configuration' do
        get services_path
        expect(response).to redirect_to(configuration_path)
      end
    end
  end
end
