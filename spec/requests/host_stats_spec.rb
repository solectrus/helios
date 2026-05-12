RSpec.describe 'HostStats', :with_admin_password do
  before do
    allow(HostStats).to receive(:snapshot)
      .and_return(HostStats::Snapshot.new(cpu_percent: 42, cpu_cores: 2, ram_percent: 75))
  end

  describe 'GET /host-stats' do
    it 'returns a turbo-stream response replacing the host-stats frame' do
      login
      get host_stats_path, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('host-stats')
      expect(response.body).to include('42 %')
      expect(response.body).to include('75 %')
    end

    it 'renders the CPU tooltip with core count' do
      login
      get host_stats_path, as: :turbo_stream, headers: { 'Accept-Language' => 'en' }

      expect(response.body).to include('CPU usage (2 cores)')
    end

    it 'falls back to the short CPU tooltip when core count is unavailable' do
      allow(HostStats).to receive(:snapshot)
        .and_return(HostStats::Snapshot.new(cpu_percent: nil, cpu_cores: nil, ram_percent: 75))

      login
      get host_stats_path, as: :turbo_stream, headers: { 'Accept-Language' => 'en' }

      expect(response.body).to include('CPU usage')
      expect(response.body).not_to include('cores')
    end

    it 'renders gracefully when host metrics are unavailable' do
      allow(HostStats).to receive(:snapshot)
        .and_return(HostStats::Snapshot.new(cpu_percent: nil, cpu_cores: nil, ram_percent: nil))

      login
      get host_stats_path, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('—')
    end
  end
end
