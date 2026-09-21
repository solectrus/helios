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
        # CGI.escapeHTML: a title may contain "&" (e.g. "Address & domain")
        expect(response.body).to include(CGI.escapeHTML(I18n.t("configurations.settings.#{setting}.title")))
      end
    end

    it 'displays a heading for every active group' do
      get settings_path

      Configuration.current.optional_groups.each_key do |group|
        # CGI.escapeHTML: group labels may contain "&" (e.g. "Zugriff & Sicherheit")
        expect(response.body).to include(CGI.escapeHTML(I18n.t("settings.show.groups.#{group}")))
      end
    end

    # Nothing labels the two tiers, so their order is what tells them apart:
    # the required chip stands above the rule, the groups below it.
    it 'leads with the required setting, ahead of the first group' do
      get settings_path

      expect(response.body.index(I18n.t('configurations.settings.system_general.title')))
        .to be < response.body.index(I18n.t('configurations.settings.deployment.title'))
    end

    # Every mode names its own required setting, so the tier is never empty.
    it 'leads with the external database in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      get settings_path

      expect(response.body.index(I18n.t('configurations.settings.influxdb.title')))
        .to be < response.body.index(I18n.t('configurations.settings.deployment.title'))
    end
  end

  # The screen was reached at /advanced up to v1.4.3.
  describe 'GET /advanced' do
    it 'sends a bookmark of the old address to the settings page' do
      get '/advanced'

      expect(response).to redirect_to(settings_path)
      expect(response).to have_http_status(:moved_permanently)
    end
  end
end
