RSpec.describe 'Services::Batches', :with_admin do
  before do
    login
    Configuration.current.complete_setup!
    allow(ComposeJob).to receive(:perform_later)
  end

  def mock_compose_services(*names)
    services = names.map { |name| mock_service(name) }
    collection = instance_double(Compose::ServiceCollection)
    allow(collection).to receive(:reject) { |&block| services.reject(&block) }
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
    services
  end

  def mock_service(name)
    instance_double(
      Compose::Service,
      name: name,
      display_name: name.capitalize,
      image: "#{name}:latest",
      public_port: nil,
      helios?: name == 'helios',
    )
  end

  def mock_containers(containers_data)
    containers = containers_data.map do |name, running|
      instance_double(
        DockerHost::Container,
        service_name: name,
        running?: running,
        status: running ? 'running' : 'exited',
        health_status: nil,
        version: '1.0.0',
        public_port: nil,
        stoppable?: running,
      )
    end
    allow(DockerHost::Container).to receive(:all).and_return(containers)
    containers
  end

  describe 'POST /services/batch (start all)' do
    it 'enqueues an up job' do
      mock_compose_services('influxdb', 'redis', 'dashboard')
      mock_containers('influxdb' => false, 'redis' => false, 'dashboard' => false)

      post batch_path

      expect(ComposeJob).to have_received(:perform_later).with(:up)
      expect(response).to redirect_to(root_path)
    end

    it 'returns turbo_stream response when requested' do
      mock_compose_services('influxdb', 'redis')
      mock_containers('influxdb' => false, 'redis' => false)

      post batch_path, as: :turbo_stream

      expect(ComposeJob).to have_received(:perform_later).with(:up)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it 'excludes helios service from pending updates' do
      mock_compose_services('influxdb', 'helios')
      mock_containers('influxdb' => false, 'helios' => true)

      post batch_path, as: :turbo_stream

      expect(response.body).to include('service-influxdb')
      expect(response.body).not_to include('service-helios')
    end
  end

  describe 'DELETE /services/batch (stop all)' do
    it 'enqueues a down job' do
      mock_compose_services('influxdb', 'redis')
      mock_containers('influxdb' => true, 'redis' => true)

      delete batch_path

      expect(ComposeJob).to have_received(:perform_later).with(:down)
      expect(response).to redirect_to(root_path)
    end

    it 'returns turbo_stream response when requested' do
      mock_compose_services('influxdb', 'redis')
      mock_containers('influxdb' => true, 'redis' => true)

      delete batch_path, as: :turbo_stream

      expect(ComposeJob).to have_received(:perform_later).with(:down)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end
  end
end
