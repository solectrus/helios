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

    it 'redirects direct browser visits to the services page' do
      login
      get status_bar_path

      expect(response).to redirect_to(services_path)
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
