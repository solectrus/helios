RSpec.describe 'Configurations::Surveys', :with_admin do
  before { login }

  describe 'GET /configuration/surveys/:id' do
    Chapter::KINDS.each do |kind|
      it "returns JSON for #{kind} survey" do
        get configuration_survey_path(id: kind)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
      end
    end

    it 'returns 404 for invalid kind' do
      get configuration_survey_path(id: 'nonexistent')

      expect(response).to have_http_status(:not_found)
    end

    Chapter::DEVICE_KINDS.each do |kind|
      it "injects name question for #{kind} survey" do
        get configuration_survey_path(id: kind)

        survey = response.parsed_body
        first_element = survey['pages'].first['elements'].first

        expect(first_element['name']).to eq('name')
        expect(first_element['type']).to eq('text')
        expect(first_element['isRequired']).to be(true)
      end
    end

    Chapter::SINGLETON_KINDS.each do |kind|
      it "does not inject name question for #{kind} survey" do
        get configuration_survey_path(id: kind)

        survey = response.parsed_body
        first_element = survey['pages'].first['elements'].first

        expect(first_element['name']).not_to eq('name')
      end
    end
  end
end
