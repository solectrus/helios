RSpec.describe 'Advanced', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /advanced' do
    it 'renders the advanced page' do
      get advanced_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays setting section titles' do
      get advanced_path

      Configuration::SETTINGS.each do |setting|
        title = I18n.t("configurations.settings.#{setting}.title")
        expect(response.body).to include(title)
      end
    end
  end
end
