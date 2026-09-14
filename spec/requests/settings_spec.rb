RSpec.describe 'Settings', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /settings' do
    it 'renders the settings page' do
      get settings_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays a chip for every visible setting' do
      get settings_path

      Configuration.current.visible_settings.each do |setting|
        expect(response.body).to include(I18n.t("configurations.settings.#{setting}.title"))
      end
    end

    it 'displays a heading for every active group' do
      get settings_path

      Configuration.current.advanced_groups.each_key do |group|
        # CGI.escapeHTML: group labels may contain "&" (e.g. "Zugriff & Sicherheit")
        expect(response.body).to include(CGI.escapeHTML(I18n.t("settings.show.groups.#{group}")))
      end
    end
  end
end
