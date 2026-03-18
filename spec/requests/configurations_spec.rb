RSpec.describe 'Configurations', :with_admin do
  before { login }

  describe 'GET /configuration' do
    it 'renders the configuration page' do
      get configuration_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays all chapter kind titles except sensors' do
      get configuration_path

      (Chapter::KINDS - %w[sensors]).each do |kind|
        title = I18n.t("configurations.chapters.#{kind}.title")
        expect(response.body).to include(title)
      end
    end

    it 'displays existing device chapters' do
      config = Configuration.current
      config.add_device('inverter', 'Dach Süd')

      get configuration_path

      expect(response.body).to include('Dach Süd')
    end
  end
end
