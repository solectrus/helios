RSpec.describe 'Configurations::Surveys', :with_admin do
  before { login }

  describe 'GET /configuration/surveys/:id' do
    (Configuration::ALL - Configuration::HIDDEN).each do |setting|
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

    Configuration::DEVICES.each do |setting|
      it "injects name question for #{setting} survey" do
        get configuration_survey_path(id: setting)

        survey = response.parsed_body
        first_element = survey['pages'].first['elements'].first

        expect(first_element['name']).to eq('name')
        expect(first_element['type']).to eq('text')
        expect(first_element['isRequired']).to be(true)
      end
    end

    (Configuration::SINGLETONS - Configuration::HIDDEN).each do |setting|
      it "does not inject name question for #{setting} survey" do
        get configuration_survey_path(id: setting)

        survey = response.parsed_body
        first_element = survey['pages'].first['elements'].first

        expect(first_element['name']).not_to eq('name')
      end
    end
  end
end
