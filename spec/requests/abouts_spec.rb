RSpec.describe 'About', :with_admin_password do
  before { login }

  describe 'GET /about' do
    it 'renders the about page' do
      get about_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('about.show.tagline'))
      expect(response.body).to include(I18n.t('about.show.license_heading'))
      expect(response.body).to include(I18n.t('about.show.components_heading'))
    end

    it 'renders the version and copyright' do
      get about_path

      expect(response.body).to include('© 2026 Georg Ledermann')
      expect(response.body).to include(I18n.t('about.show.version_label'))
    end

    it 'lists bundled components from THIRD_PARTY_LICENSES.md' do
      get about_path

      # Components are parsed from the bundled markdown table; rake (always in
      # the default group) is a stable check that the table reached the view.
      expect(response.body).to include('rake')
    end
  end

  describe 'GET /about/component' do
    it 'renders a gem component inside a turbo frame' do
      get about_component_path(category: 'gem', name: 'rake'),
          headers: turbo_frame_headers('about-modal-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('about-modal-content')
      expect(response.body).to include('rake')
    end

    it 'returns 404 for an unknown component' do
      get about_component_path(category: 'gem', name: 'definitely-not-a-real-gem'),
          headers: turbo_frame_headers('about-modal-content')

      expect(response).to have_http_status(:not_found)
    end
  end
end
