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

  def mock_container(service_name, running: true, status: nil)
    effective_status = status || (running ? 'running' : 'exited')
    instance_double(
      Orchestration::Container,
      service_name: service_name,
      running?: running,
      status: effective_status,
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

    it 'disables the logs button when the container is in created state' do
      mock_compose_service('influxdb')
      container = mock_container('influxdb', running: false, status: 'created')
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(container)

      get service_row_path(service_id: 'influxdb'), headers: turbo_frame_headers

      expect(response.body).to match(/<span[^>]*\bbtn-disabled\b[^>]*>\s*<i[^>]*fa-file-lines/)
    end

    it 'enables the logs button for an exited container' do
      mock_compose_service('influxdb')
      container = mock_container('influxdb', running: false, status: 'exited')
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(container)

      get service_row_path(service_id: 'influxdb'), headers: turbo_frame_headers

      expect(response.body).to include(service_log_path('influxdb'))
    end

    it 'disables the start button and shows a warning link when the collector source is incompletely configured' do
      Configuration.current.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      mock_compose_service('forecast-collector')
      allow(Orchestration::Container).to receive(:find).with('forecast-collector').and_return(nil)

      get service_row_path(service_id: 'forecast-collector'), headers: turbo_frame_headers

      expect(response.body).to include(I18n.t('configurations.show.incomplete'))
      expect(response.body).to include(%(href="#{datasources_path}"))
      expect(response.body).to match(/<button[^>]*\bdisabled\b/)
    end
  end
end
