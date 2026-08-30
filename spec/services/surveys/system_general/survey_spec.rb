RSpec.describe Surveys::SystemGeneral::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    it 'exposes installation_date and timezone in full mode' do
      expect(find_survey_element(result, 'installation_date')).to be_present
      expect(find_survey_element(result, 'timezone')).to include('defaultValue' => 'Europe/Berlin')
    end

    it 'hides installation_date in collectors_only mode (no local PV)' do
      Configuration.current.update('deployment', { 'mode' => 'collectors_only' })

      expect(find_survey_element(result, 'installation_date')).to be_nil
      expect(find_survey_element(result, 'timezone')).to be_present
    end

    describe 'currency' do
      it 'offers the preset dropdown and a single free-text field' do
        expect(section_names(result)).to eq(%w[p_general p_currency])
        expect(find_survey_element(result, 'currency_preset')).to include('type' => 'dropdown')
        currency = find_survey_element(result, 'currency')
        expect(currency).to include('type' => 'text', 'visibleIf' => "{currency_preset} = 'other'")
      end

      it 'announces itself in the header' do
        expect(result['description']['default']).to include('currency')
      end
    end
  end
end
