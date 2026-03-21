RSpec.describe 'Configurations::Surveys', :with_admin_password do
  before { login }

  describe 'GET /configuration/surveys/:id' do
    (Configuration::ALL - Configuration::HIDDEN).each do |setting|
      next if setting == 'sensors' # sensors is dynamic, no survey file

      it "returns JSON for #{setting} survey" do
        get configuration_survey_path(id: setting)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
      end
    end

    it 'returns 404 for invalid setting' do
      get configuration_survey_path(id: 'nonexistent')

      expect(response).to have_http_status(:not_found)
    end

    it 'returns sensor survey with dynamic source choices' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      expect(response).to have_http_status(:ok)
      survey = response.parsed_body
      source_page = survey['pages'].first
      source_element = source_page['elements'].find { |e| e['name'] == 'source' }

      expect(source_element['choices']).to be_present
      expect(source_element['choices'].pluck('value')).to include('senec')
    end

    it 'returns 404 for sensor survey without sensor param' do
      get configuration_survey_path(id: 'sensor')

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for sensor survey with invalid sensor' do
      get configuration_survey_path(id: 'sensor', params: { sensor: 'invalid_sensor' })

      expect(response).to have_http_status(:not_found)
    end
  end
end
