require 'rails_helper'

RSpec.describe 'Services::Rows', :with_admin do
  before do
    login
    Configuration.current.complete_setup!
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
    collection = instance_double(Compose::ServiceCollection)
    allow(collection).to receive(:find).with(name).and_return(service)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
    service
  end

  def mock_container(service_name, running: true)
    instance_double(
      DockerHost::Container,
      service_name: service_name,
      running?: running,
      status: running ? 'running' : 'exited',
      health_status: nil,
      version: '1.0.0',
      public_port: nil,
      stoppable?: running,
    )
  end

  describe 'GET /services/:service_id/row' do
    it 'renders the service row component for a running service' do
      mock_compose_service('influxdb')
      container = mock_container('influxdb', running: true)
      allow(DockerHost::Container).to receive(:find).with('influxdb').and_return(container)

      get service_row_path(service_id: 'influxdb')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('influxdb')
    end

    it 'renders the service row component for a stopped service' do
      mock_compose_service('redis')
      container = mock_container('redis', running: false)
      allow(DockerHost::Container).to receive(:find).with('redis').and_return(container)

      get service_row_path(service_id: 'redis')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('redis')
    end

    it 'renders the service row component when no container exists' do
      mock_compose_service('postgresql')
      allow(DockerHost::Container).to receive(:find).with('postgresql').and_return(nil)

      get service_row_path(service_id: 'postgresql')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('postgresql')
    end
  end
end
