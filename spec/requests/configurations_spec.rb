RSpec.describe 'Configurations', :with_admin do
  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration' do
    it 'renders the configuration page' do
      get configuration_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays all visible setting titles' do
      get configuration_path

      (Configuration::ALL - Configuration::HIDDEN).each do |setting|
        title = I18n.t("configurations.settings.#{setting}.title")
        expect(response.body).to include(title)
      end
    end

    it 'displays existing devices' do
      config = Configuration.current
      config.add('inverter', 'dach-sued', { 'name' => 'Dach Süd' })

      get configuration_path

      expect(response.body).to include('Dach Süd')
    end
  end
end
