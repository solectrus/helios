RSpec.describe 'Services::Batches', :with_admin_password do
  before do
    login
    with_startable_config_yaml
    allow(ComposeJob).to receive(:perform_later)
    # Reading the real answer needs Docker. Its own spec covers what it reads.
    allow(Orchestration::SelfPorts).to receive(:drifted?).and_return(false)
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
    containers = containers_data.map { |name, running| mock_container_double(name, running) }
    allow(Orchestration::Container).to receive(:all).and_return(containers)
    containers
  end

  def mock_container_double(name, running)
    instance_double(
      Orchestration::Container,
      service_name: name,
      running?: running,
      status: running ? 'running' : 'exited',
      effective_status: running ? :ok : :stopped,
      health_status: nil,
      version: '1.0.0',
      public_port: nil,
      stoppable?: running,
      image: "#{name}:latest",
    )
  end

  describe 'POST /services/batch (start all)' do
    it 'enqueues an up job' do
      mock_compose_services('influxdb', 'redis', 'dashboard')
      mock_containers('influxdb' => false, 'redis' => false, 'dashboard' => false)

      post batch_path

      expect(ComposeJob).to have_received(:perform_later).with(:up)
      expect(response).to redirect_to(services_path)
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

    # Choosing the built-in Traefik moves the host port of HELIOS to Traefik.
    # Only a run that carries HELIOS hands that port over, and HELIOS ends with
    # it, so the answer is the restart screen instead of a row update.
    context 'when the host port of HELIOS moves' do
      before do
        allow(Orchestration::SelfPorts).to receive(:drifted?).and_return(true)
        mock_compose_services('influxdb', 'traefik', 'helios')
        mock_containers('influxdb' => true, 'traefik' => false, 'helios' => true)
      end

      it 'enqueues a converge that carries HELIOS' do
        post batch_path

        expect(ComposeJob).to have_received(:perform_later).with(:self_converge)
        expect(ComposeJob).not_to have_received(:perform_later).with(:up)
      end

      it 'sends the reader to the restart screen, told the address moves' do
        post batch_path

        expect(response).to redirect_to(
          restarting_path(boot_id: Rails.application.config.boot_id, moved: true),
        )
      end

      it 'redirects a turbo_stream request the same way' do
        post batch_path, as: :turbo_stream

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
      end
    end

    # The stack that owns the shared network is not this one, so the network
    # can go after the save that named it. Compose would refuse the whole run,
    # and the run that hands port 3999 over would take HELIOS with it.
    context 'when the shared network of the proxy is gone' do
      before do
        with_startable_config_yaml(
          'system' => { 'app_host' => 'solar.example.com' },
          'reverse_proxy' => { 'mode' => 'external', 'proxy_network' => 'edge' },
        )
        allow(Orchestration::DockerCli).to receive(:network_names).and_return(%w[bridge])
      end

      it 'starts nothing and names the network' do
        post batch_path

        expect(ComposeJob).not_to have_received(:perform_later)
        expect(flash[:alert]).to include('edge')
      end

      it 'sends the reader back to the services screen' do
        post batch_path

        expect(response).to redirect_to(services_path)
      end
    end

    # Docker out of reach is not a missing network, and a start that Docker
    # cannot answer for fails where it says so itself.
    context 'when Docker does not answer' do
      before do
        with_startable_config_yaml(
          'system' => { 'app_host' => 'solar.example.com' },
          'reverse_proxy' => { 'mode' => 'external', 'proxy_network' => 'edge' },
        )
        allow(Orchestration::DockerCli).to receive(:network_names).and_return(nil)
        mock_compose_services('influxdb')
        mock_containers('influxdb' => false)
      end

      it 'starts the stack' do
        post batch_path

        expect(ComposeJob).to have_received(:perform_later).with(:up)
      end
    end

    it 'is blocked while the configuration is incomplete' do
      with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' }) # no sensor, no installation date

      post batch_path

      expect(ComposeJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(services_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe 'DELETE /services/batch (stop all)' do
    before do
      allow(Orchestration::StackStatus).to receive(:mark_stopping!)
    end

    it 'enqueues a down job' do
      mock_compose_services('influxdb', 'redis')
      mock_containers('influxdb' => true, 'redis' => true)

      delete batch_path

      expect(Orchestration::StackStatus).to have_received(:mark_stopping!)
      expect(ComposeJob).to have_received(:perform_later).with(:down)
      expect(response).to redirect_to(services_path)
    end

    it 'returns turbo_stream response when requested' do
      mock_compose_services('influxdb', 'redis')
      mock_containers('influxdb' => true, 'redis' => true)

      delete batch_path, as: :turbo_stream

      expect(Orchestration::StackStatus).to have_received(:mark_stopping!)
      expect(ComposeJob).to have_received(:perform_later).with(:down)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end
  end
end
