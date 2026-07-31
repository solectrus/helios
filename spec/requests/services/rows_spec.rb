RSpec.describe 'Services::Rows', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
  end

  def mock_compose_service(name, public_port: nil)
    service = instance_double(
      Compose::Service,
      name: name,
      display_name: name.capitalize,
      image: "#{name}:latest",
      public_port:,
      helios?: name == 'helios',
    )
    collection = mock_service_collection([service])
    allow(collection).to receive(:find).with(name).and_return(service)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
    service
  end

  def mock_container(service_name, running: true, status: nil, public_port: nil)
    effective_status = status || (running ? 'running' : 'exited')
    instance_double(
      Orchestration::Container,
      service_name: service_name,
      running?: running,
      status: effective_status,
      health_status: nil,
      version: '1.0.0',
      public_port:,
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

    describe 'the "Open" button' do
      it 'opens a host port for a service that publishes one' do
        mock_compose_service('dashboard', public_port: 3000)
        container = mock_container('dashboard', running: true, public_port: 3000)
        allow(Orchestration::Container).to receive(:find).with('dashboard').and_return(container)

        get service_row_path(service_id: 'dashboard'), headers: turbo_frame_headers

        expect(response.body).to include('data-port="3000"')
        expect(response.body).not_to include('data-url')
      end

      it 'opens the public HTTPS domain for the dashboard behind a managed Traefik' do
        with_config_yaml(
          'system' => { 'timezone' => 'Europe/Berlin' },
          'reverse_proxy' => { 'app_domain' => 'solectrus.example.com' },
        )
        # Behind a managed Traefik the dashboard publishes no host port.
        mock_compose_service('dashboard')
        container = mock_container('dashboard', running: true)
        allow(Orchestration::Container).to receive(:find).with('dashboard').and_return(container)

        get service_row_path(service_id: 'dashboard'), headers: turbo_frame_headers

        expect(response.body).to include('data-url="https://solectrus.example.com"')
        expect(response.body).not_to include('data-port')
      end

      it 'opens the public HTTPS domain with the InfluxDB port when exposed behind a managed Traefik' do
        with_config_yaml(
          'system' => { 'timezone' => 'Europe/Berlin' },
          'reverse_proxy' => { 'app_domain' => 'solectrus.example.com' },
          'influxdb' => { 'publish_port' => true, 'host_port' => '18086' },
        )
        # Routed via Traefik's influxdb entrypoint, so influxdb publishes no
        # host port of its own.
        mock_compose_service('influxdb')
        container = mock_container('influxdb', running: true)
        allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(container)

        get service_row_path(service_id: 'influxdb'), headers: turbo_frame_headers

        expect(response.body).to include('data-url="https://solectrus.example.com:18086"')
      end

      it 'shows no button for InfluxDB behind a managed Traefik when it is not exposed' do
        with_config_yaml(
          'system' => { 'timezone' => 'Europe/Berlin' },
          'reverse_proxy' => { 'app_domain' => 'solectrus.example.com' },
        )
        mock_compose_service('influxdb')
        container = mock_container('influxdb', running: true)
        allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(container)

        get service_row_path(service_id: 'influxdb'), headers: turbo_frame_headers

        expect(response.body).not_to include('open-external#open')
      end

      it 'never shows the button for Traefik itself, even when it publishes ports' do
        mock_compose_service('traefik', public_port: 443)
        container = mock_container('traefik', running: true, public_port: 443)
        allow(Orchestration::Container).to receive(:find).with('traefik').and_return(container)

        get service_row_path(service_id: 'traefik'), headers: turbo_frame_headers

        expect(response.body).not_to include('open-external#open')
      end

      it 'opens the proxy domain instead of the host port behind an external Traefik' do
        with_config_yaml(
          'system' => { 'timezone' => 'Europe/Berlin', 'app_host' => 'solectrus.example.com' },
          'reverse_proxy' => { 'bind_ip' => '10.0.0.5' },
        )
        # External mode still publishes a host port; the button should prefer
        # the proxy URL over the raw http://host:port.
        mock_compose_service('dashboard', public_port: 3000)
        container = mock_container('dashboard', running: true, public_port: 3000)
        allow(Orchestration::Container).to receive(:find).with('dashboard').and_return(container)

        get service_row_path(service_id: 'dashboard'), headers: turbo_frame_headers

        expect(response.body).to include('data-url="https://solectrus.example.com"')
        expect(response.body).not_to include('data-port')
      end

      it 'falls back to the host port behind an external Traefik without app_host' do
        with_config_yaml(
          'system' => { 'timezone' => 'Europe/Berlin' },
          'reverse_proxy' => { 'bind_ip' => '10.0.0.5' },
        )
        mock_compose_service('dashboard', public_port: 3000)
        container = mock_container('dashboard', running: true, public_port: 3000)
        allow(Orchestration::Container).to receive(:find).with('dashboard').and_return(container)

        get service_row_path(service_id: 'dashboard'), headers: turbo_frame_headers

        expect(response.body).to include('data-port="3000"')
        expect(response.body).not_to include('data-url')
      end
    end

    describe 'the power splitter row' do
      before do
        mock_compose_service('power-splitter')
        container = mock_container('power-splitter', running: true)
        allow(Orchestration::Container).to receive(:find).with('power-splitter').and_return(container)
        allow(Orchestration::PowerSplitter::Progress).to receive(:call).and_return(nil)
      end

      it 'offers the recalculation button' do
        get service_row_path(service_id: 'power-splitter'), headers: turbo_frame_headers

        expect(response.body).to include(service_recalculation_path('power-splitter'))
      end

      it 'shows no progress badge while nothing is being recalculated' do
        get service_row_path(service_id: 'power-splitter'), headers: turbo_frame_headers

        expect(response.body).to include('data-service-row--component-recalculating-value="false"')
        expect(response.body).not_to include('service-power-splitter-recalculation-progress')
      end

      it 'shows the percentage while a recalculation is running' do
        allow(Orchestration::PowerSplitter::Progress).to receive(:call).and_return(
          Orchestration::PowerSplitter::Progress::Snapshot.new(day: Date.new(2026, 7, 22), percent: 30),
        )

        get service_row_path(service_id: 'power-splitter'), headers: turbo_frame_headers

        aggregate_failures do
          expect(response.body).to include('data-service-row--component-recalculating-value="true"')
          expect(response.body).to include('service-power-splitter-recalculation-progress')
          expect(response.body).to include('30%')
        end
      end

      it 'replaces the button with the progress while a recalculation is running' do
        allow(Orchestration::PowerSplitter::Progress).to receive(:call).and_return(
          Orchestration::PowerSplitter::Progress::Snapshot.new(day: Date.new(2026, 7, 22), percent: 30),
        )

        get service_row_path(service_id: 'power-splitter'), headers: turbo_frame_headers

        expect(response.body).not_to include(service_recalculation_path('power-splitter'))
      end

      it 'disables the button while the service is not running' do
        allow(Orchestration::Container).to receive(:find).with('power-splitter').and_return(
          mock_container('power-splitter', running: false),
        )

        get service_row_path(service_id: 'power-splitter'), headers: turbo_frame_headers

        expect(recalculation_button(response.body)).to match(/\bdisabled\b/)
      end

      it 'offers the button while nothing is being recalculated' do
        get service_row_path(service_id: 'power-splitter'), headers: turbo_frame_headers

        expect(recalculation_button(response.body)).not_to match(/\bdisabled\b/)
      end

      def recalculation_button(body)
        body[%r{<form[^>]*#{Regexp.escape(service_recalculation_path('power-splitter'))}.*?</form>}m]
      end
    end

    describe 'the Watchtower row while automatic updates are paused' do
      before do
        # A pending operation would take precedence over the pause label, and
        # the store is process-wide — drop whatever an earlier spec left behind.
        Orchestration::PendingOperations.clear('watchtower')
        mock_compose_service('watchtower')
        allow(Orchestration::Container).to receive(:find).with('watchtower')
                                                         .and_return(mock_container('watchtower', running: false,
                                                                                                  status: 'paused'))
        allow(Orchestration::UpdatePause).to receive(:paused?).and_return(true)
      end

      # Docker reports the frozen container as `paused`, so the row renders it
      # through the ordinary status path — same wording and styling as every
      # other state. Sidecar translations live in the component's own I18n
      # backend, hence the rendered copy instead of a global key.
      it 'reports the container as paused' do
        get service_row_path(service_id: 'watchtower'), headers: turbo_frame_headers

        aggregate_failures do
          expect(response.body).to include('data-tip="Paused"')
          expect(response.body).to include('bg-info')
          expect(response.body).not_to include('Not created')
        end
      end

      it 'does not offer to start the service' do
        get service_row_path(service_id: 'watchtower'), headers: turbo_frame_headers

        expect(start_button(response.body)).to match(/\bdisabled\b/)
      end

      def start_button(body)
        body[%r{<form[^>]*#{Regexp.escape(service_task_path('watchtower'))}.*?</form>}m]
      end
    end

    it 'does not read the log of other services' do
      mock_compose_service('redis')
      container = mock_container('redis', running: true)
      allow(Orchestration::Container).to receive(:find).with('redis').and_return(container)
      allow(Orchestration::PowerSplitter::Progress).to receive(:call)

      get service_row_path(service_id: 'redis'), headers: turbo_frame_headers

      expect(Orchestration::PowerSplitter::Progress).not_to have_received(:call)
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
