RSpec.describe 'Restarting', :with_admin_password do
  before { with_config_yaml }

  # Shown while HELIOS restarts itself, so it must render without a session
  # and without the application layout (the assets may be reloading too).
  describe 'GET /restarting' do
    it 'renders the standalone waiting page for an anonymous visitor' do
      get restarting_path(boot_id: 'abc123')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('abc123')
      expect(response.body).to include(I18n.t('restarting.show.title'))
    end
  end
end
