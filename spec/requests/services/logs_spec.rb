RSpec.describe 'Services::Logs', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
    mock_compose_service('influxdb')
  end

  def mock_compose_service(name)
    service = instance_double(
      Compose::Service,
      name: name,
      display_name: name.capitalize,
      helios?: false,
    )
    collection = mock_service_collection([service])
    allow(collection).to receive(:find).with(name).and_return(service)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
    service
  end

  def mock_logs(output)
    allow(Orchestration::Runner).to receive(:logs).and_return(
      Orchestration::CommandResult.new(output:, exit_status: 0),
    )
  end

  describe 'GET /services/:service_id/log' do
    it 'renders the full log view' do
      mock_logs("influxdb-1  | 2024-03-23T14:30:05.000000000Z started\n")

      get service_log_path(service_id: 'influxdb'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('turbo-frame')
      expect(response.body).to include('15:30:05') # UTC+1 (Europe/Berlin, CET)
    end

    it 'redirects non-frame requests to services' do
      get service_log_path(service_id: 'influxdb')

      expect(response).to redirect_to(services_path)
    end

    # Regression: every String operation on the output (blank?, match?,
    # html_escape) raised on the invalid byte and the log page returned a 500.
    it 'repairs non-UTF-8 log output' do
      mock_logs("influxdb-1  | 2024-03-23T14:30:05.000000000Z Gr\xFCn\n")

      get service_log_path(service_id: 'influxdb'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Grün')
    end

    context 'with until parameter' do
      it 'returns only the HTML fragment' do
        mock_logs("influxdb-1  | 2024-03-23T14:29:00.000000000Z older line\n")

        get service_log_path(service_id: 'influxdb'),
            params: { until: '2024-03-23T14:30:05.000000000Z' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('15:29:00') # UTC+1 (Europe/Berlin, CET)
        expect(response.body).not_to include('turbo-frame')
      end

      it 'repairs non-UTF-8 log output' do
        mock_logs("influxdb-1  | 2024-03-23T14:29:00.000000000Z Gr\xFCn\n")

        get service_log_path(service_id: 'influxdb'),
            params: { until: '2024-03-23T14:30:05.000000000Z' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Grün')
      end

      it 'passes until_timestamp to runner' do
        mock_logs('')

        get service_log_path(service_id: 'influxdb'),
            params: { until: '2024-03-23T14:30:05.000000000Z' }

        expect(Orchestration::Runner).to have_received(:logs).with(
          hash_including(until_timestamp: '2024-03-23T14:30:05.000000000Z'),
        )
      end

      it 'returns empty body when no older logs exist' do
        mock_logs('')

        get service_log_path(service_id: 'influxdb'),
            params: { until: '2024-03-23T14:30:05.000000000Z' }

        expect(response).to have_http_status(:ok)
        expect(response.body.strip).to be_empty
      end

      it 'limits response to TAIL_LINES' do
        many_lines = Array.new(300) do |i|
          "influxdb-1  | 2024-03-23T14:#{format('%02d', i / 60)}:#{format('%02d', i % 60)}.000000000Z line #{i}"
        end
        mock_logs(many_lines.join("\n"))

        get service_log_path(service_id: 'influxdb'),
            params: { until: '2024-03-23T14:30:05.000000000Z' }

        expect(response.body.scan('class="block whitespace-pre"').size).to eq(200)
      end
    end

    context 'when command fails' do
      before do
        allow(Orchestration::Runner).to receive(:logs).and_raise(
          Orchestration::Runner::CommandError.new('failed', stdout: 'error output'),
        )
      end

      it 'renders error in the full view' do
        get service_log_path(service_id: 'influxdb'), headers: turbo_frame_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('error output')
      end

      it 'returns empty body for until requests' do
        get service_log_path(service_id: 'influxdb'),
            params: { until: '2024-03-23T14:30:05.000000000Z' }

        expect(response).to have_http_status(:ok)
        expect(response.body.strip).to be_empty
      end

      it 'repairs non-UTF-8 error output' do
        allow(Orchestration::Runner).to receive(:logs).and_raise(
          Orchestration::Runner::CommandError.new('failed', stdout: "Gr\xFCn"),
        )

        get service_log_path(service_id: 'influxdb'), headers: turbo_frame_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Grün')
      end
    end
  end
end
