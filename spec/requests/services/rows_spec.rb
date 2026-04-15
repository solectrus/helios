RSpec.describe 'Services::Rows', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
  end

  def mock_compose_service(name)
    service = instance_double(
      Compose::Service,
      name: name,
      display_name: name.capitalize,
      image: "#{name}:latest",
      public_port: nil,
      helios?: name == 'helios',
    )
    collection = mock_service_collection([service])
    allow(collection).to receive(:find).with(name).and_return(service)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
    service
  end

  def mock_container(service_name, running: true)
    instance_double(
      Orchestration::Container,
      service_name: service_name,
      running?: running,
      status: running ? 'running' : 'exited',
      health_status: nil,
      version: '1.0.0',
      public_port: nil,
      stoppable?: running,
      image: "#{service_name}:latest",
    )
  end

  describe 'GET /services/:service_id/row' do
    it 'renders the service row component for a running service' do
      mock_compose_service('influxdb')
      container = mock_container('influxdb', running: true)
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(container)

      get service_row_path(service_id: 'influxdb'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('influxdb')
    end

    it 'renders the service row component for a stopped service' do
      mock_compose_service('redis')
      container = mock_container('redis', running: false)
      allow(Orchestration::Container).to receive(:find).with('redis').and_return(container)

      get service_row_path(service_id: 'redis'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('redis')
    end

    it 'renders the service row component when no container exists' do
      mock_compose_service('postgresql')
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(nil)

      get service_row_path(service_id: 'postgresql'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('postgresql')
    end

    it 'redirects non-frame requests to services' do
      get service_row_path(service_id: 'influxdb')

      expect(response).to redirect_to(services_path)
    end
  end
end
