RSpec.describe 'Configurations', :with_admin do
  before { login }

  describe 'GET /configuration' do
    it 'renders the configuration page' do
      get configuration_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays all chapter names' do
      get configuration_path

      Chapter::NAMES.each do |chapter_name|
        expect(response.body).to include(chapter_name)
      end
    end
  end
end
