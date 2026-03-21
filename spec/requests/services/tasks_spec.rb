RSpec.describe 'Services::Tasks', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
    allow(ComposeJob).to receive(:perform_later)
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
    )
  end

  describe 'POST /services/:service_id/task (start)' do
    it 'enqueues a start job and returns pending status' do
      mock_compose_service('influxdb')
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(nil)

      post service_task_path(service_id: 'influxdb')

      expect(ComposeJob).to have_received(:perform_later).with(:start, 'influxdb')
      expect(response).to redirect_to(services_path)
    end

    it 'returns turbo_stream response when requested' do
      mock_compose_service('influxdb')
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(nil)

      post service_task_path(service_id: 'influxdb'), as: :turbo_stream

      expect(ComposeJob).to have_received(:perform_later).with(:start, 'influxdb')
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it 'rejects start on helios service' do
      mock_compose_service('helios')
      allow(Orchestration::Container).to receive(:find).with('helios').and_return(nil)

      post service_task_path(service_id: 'helios')

      expect(ComposeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /services/:service_id/task (recreate)' do
    it 'enqueues a recreate job' do
      mock_compose_service('redis')
      container = mock_container('redis', running: true)
      allow(Orchestration::Container).to receive(:find).with('redis').and_return(container)

      patch service_task_path(service_id: 'redis')

      expect(ComposeJob).to have_received(:perform_later).with(:recreate, 'redis')
      expect(response).to redirect_to(services_path)
    end

    it 'rejects recreate on helios service' do
      mock_compose_service('helios')

      patch service_task_path(service_id: 'helios')

      expect(ComposeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /services/:service_id/task (stop)' do
    it 'enqueues a stop job' do
      mock_compose_service('postgresql')
      container = mock_container('postgresql', running: true)
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(container)

      delete service_task_path(service_id: 'postgresql')

      expect(ComposeJob).to have_received(:perform_later).with(:stop, 'postgresql')
      expect(response).to redirect_to(services_path)
    end

    it 'rejects stop on helios service' do
      mock_compose_service('helios')

      delete service_task_path(service_id: 'helios')

      expect(ComposeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
