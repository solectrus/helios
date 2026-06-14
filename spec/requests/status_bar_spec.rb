RSpec.describe 'StatusBar', :with_admin_password do
  describe 'GET /status-bar' do
    it 'renders the status bar frame for Turbo Frame requests' do
      login
      get status_bar_path, headers: { 'Turbo-Frame' => 'status-bar' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<turbo-frame[^>]*id="status-bar"/)
      expect(response.body).to include('data-locale="en"')
      expect(response.body).to include('data-locale="de"')
    end

    # Both locales are rendered (the frame is broadcast to clients of either
    # language), but the non-active one carries `hidden` so the correct
    # language already shows at first paint, before the locale-switching CSS
    # loads. Specs run in :en, so the German spans must be hidden.
    it 'marks the non-active locale hidden to avoid a language flash' do
      login
      get status_bar_path, headers: { 'Turbo-Frame' => 'status-bar' }

      expect(response.body).to include('data-locale="de" hidden')
      expect(response.body).not_to include('data-locale="en" hidden')
    end

    it 'redirects direct browser visits to the services page' do
      login
      get status_bar_path

      expect(response).to redirect_to(services_path)
    end

    describe 'the "Open dashboard" shortcut' do
      let(:frame_header) { { 'Turbo-Frame' => 'status-bar' } }

      # Drive the dashboard's reachability through the cached StackStatus the
      # status bar reads, and supply a real compose collection so the port is
      # resolved through the actual ServiceCollection#find API.
      def stub_dashboard(status:, public_port: nil)
        allow(Orchestration::StackStatus).to receive(:status_for)
          .with('dashboard').and_return(status)
        config = { 'image' => 'ghcr.io/solectrus/solectrus:latest' }
        config['ports'] = ["#{public_port}:3000"] if public_port
        collection = Compose::ServiceCollection.new('dashboard' => config)
        allow(Compose).to receive(:load).and_return(
          instance_double(Compose::File, services: collection),
        )
      end

      it 'shows a prominent button linking to the host port when reachable' do
        login
        stub_dashboard(status: :ok, public_port: 3001)

        get status_bar_path, headers: frame_header

        expect(response.body).to include('open-external#open')
        expect(response.body).to include('data-port="3001"')
        expect(response.body).to include('Open dashboard')
        expect(response.body).to include('Dashboard öffnen')
      end

      it 'links to the public URL behind a managed Traefik' do
        login
        with_config_yaml(
          'system' => { 'timezone' => 'Europe/Berlin' },
          'reverse_proxy' => { 'app_domain' => 'solectrus.example.com' },
        )
        stub_dashboard(status: :ok, public_port: nil)

        get status_bar_path, headers: frame_header

        expect(response.body).to include('data-url="https://solectrus.example.com"')
        expect(response.body).not_to include('data-port')
      end

      it 'hides the button while the dashboard is still starting' do
        login
        stub_dashboard(status: :starting, public_port: 3001)

        get status_bar_path, headers: frame_header

        expect(response.body).not_to include('open-external#open')
      end

      it 'hides the button when the dashboard is stopped' do
        login
        stub_dashboard(status: :stopped)

        get status_bar_path, headers: frame_header

        expect(response.body).not_to include('open-external#open')
      end

      it 'keeps the dashboard prominent and collapses stack actions into a dropdown' do
        login
        allow(Orchestration::StackStatus).to receive(:overall).and_return(:ok)
        stub_dashboard(status: :ok, public_port: 3001)

        get status_bar_path, headers: frame_header

        # Dashboard stays the one prominent button...
        expect(response.body).to include('open-external#open')
        # ...while Stop moves into the "more actions" dropdown.
        expect(response.body).to include('class="dropdown')
        expect(response.body).to include('More actions')
        expect(response.body).to include('action="/services/batch"')
        expect(response.body).to include('name="_method" value="delete"')
      end

      it 'shows a single Start button without a dropdown when the stack is stopped' do
        login
        with_startable_config_yaml
        allow(Orchestration::StackStatus).to receive(:overall).and_return(:stopped)
        allow(Orchestration::StackStatus).to receive(:status_for)
          .with('dashboard').and_return(:stopped)

        get status_bar_path, headers: frame_header

        expect(response.body).to include('/services/batch') # the Start form
        # A lone button is spelled out, just like the dropdown items.
        expect(response.body).to include('Start all services')
        expect(response.body).to include('Alle Dienste starten')
        expect(response.body).not_to include('More actions')
        expect(response.body).not_to include('open-external#open')
      end

      it 'spells out the start button as "missing" when only some services run' do
        login
        with_startable_config_yaml
        allow(Orchestration::StackStatus).to receive_messages(
          overall: :partial,
          service_counts: { running: 1, total: 10 },
        )
        allow(Orchestration::StackStatus).to receive(:status_for)
          .with('dashboard').and_return(:stopped)

        get status_bar_path, headers: frame_header

        expect(response.body).to include('/services/batch') # the Start form
        expect(response.body).to include('Start missing services')
        expect(response.body).to include('Fehlende Dienste starten')
        # The generic "all services" wording must not leak into the partial state.
        expect(response.body).not_to include('Start all services')
      end

      it 'invalidates the cached response when the dashboard becomes reachable' do
        login
        stub_dashboard(status: :starting, public_port: 3001)

        get status_bar_path, headers: frame_header
        etag = response.headers['etag']

        # Dashboard finishes its healthcheck: the button must now appear, so the
        # previously cached (button-less) response is no longer valid.
        stub_dashboard(status: :ok, public_port: 3001)
        get status_bar_path, headers: frame_header.merge('If-None-Match' => etag)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('open-external#open')
      end
    end

    it 'returns a fresh response when the HELIOS version changes' do
      login
      frame_header = { 'Turbo-Frame' => 'status-bar' }

      get status_bar_path, headers: frame_header
      etag = response.headers['etag']

      # Same version: cached response is still valid
      get status_bar_path,
          headers: frame_header.merge('If-None-Match' => etag)
      expect(response).to have_http_status(:not_modified)

      # New version after an update: response must not be cached
      allow(Rails.configuration.x.git).to receive(:commit_version).and_return(
        'v9.9.9',
      )
      get status_bar_path,
          headers: frame_header.merge('If-None-Match' => etag)
      expect(response).to have_http_status(:ok)
    end
  end
end
