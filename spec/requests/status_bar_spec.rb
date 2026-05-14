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
  end
end
