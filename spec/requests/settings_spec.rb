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

      Configuration.current.grouped_settings.each_key do |group|
        # CGI.escapeHTML: group labels may contain "&" (e.g. "Zugriff & Sicherheit")
        expect(response.body).to include(CGI.escapeHTML(I18n.t("settings.show.groups.#{group}")))
      end
    end

    # Nothing on this screen can be open: the commissioning screen asks for
    # what the mode needs before this one is reachable (see
    # CommissioningController).
    it 'carries no warning sign' do
      get settings_path

      # The dialog that asks about unsaved changes carries one of its own, and
      # it is no open setting.
      signs = response.parsed_body.css('turbo-frame#tab-content i.fa-triangle-exclamation')
                      .reject { |sign| sign.ancestors('.modal-box').any? }
      expect(signs).to be_empty
    end

    # The installation group opens the screen, and the basics come right after
    # the mode the whole installation rests on.
    it 'puts the basics second in the installation group' do
      get settings_path

      mode = response.body.index(I18n.t('configurations.settings.deployment.title'))
      basics = response.body.index(I18n.t('configurations.settings.system_general.title'))
      software = response.body.index(I18n.t('configurations.settings.software.title'))

      expect([mode, basics, software]).to eq([mode, basics, software].sort)
    end

    # The database this card configures runs on another host, and the address
    # of the one the collectors write to is asked for with the mode.
    it 'drops the InfluxDB chip in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
                       'influxdb' => { 'host' => 'influx.example.com' })

      get settings_path

      expect(response.body).not_to include(I18n.t('configurations.settings.influxdb.title'))
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
