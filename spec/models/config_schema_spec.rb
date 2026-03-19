RSpec.describe ConfigSchema do
  describe '.fields_for' do
    it 'returns fields for system' do
      fields = described_class.fields_for('system')
      expect(fields).to include('timezone', 'installation_date', 'postgres_password', 'dashboard_image')
    end

    it 'returns fields for inverter' do
      fields = described_class.fields_for('inverter')
      expect(fields).to include('battery_vendor', 'senec_host', 'senec_interval')
    end

    it 'returns fields for consumer' do
      fields = described_class.fields_for('consumer')
      expect(fields).to include('data_source', 'shelly_host', 'shelly_interval')
    end

    it 'returns :dynamic for sensors' do
      expect(described_class.fields_for('sensors')).to eq(:dynamic)
    end

    it 'returns nil for unknown setting' do
      expect(described_class.fields_for('unknown')).to be_nil
    end
  end

  describe '.valid_field?' do
    it 'returns true for known system fields' do
      expect(described_class.valid_field?('system', 'timezone')).to be true
    end

    it 'returns true for system secrets' do
      expect(described_class.valid_field?('system', 'postgres_password')).to be true
    end

    it 'returns true for image overrides' do
      expect(described_class.valid_field?('system', 'dashboard_image')).to be true
    end

    it 'returns false for unknown system field' do
      expect(described_class.valid_field?('system', 'nonsense')).to be false
    end

    it 'returns true for known inverter fields' do
      expect(described_class.valid_field?('inverter', 'battery_vendor')).to be true
    end

    it 'returns false for unknown inverter field' do
      expect(described_class.valid_field?('inverter', 'nonsense')).to be false
    end

    it 'returns true for any sensor field (dynamic)' do
      expect(described_class.valid_field?('sensors', 'anything')).to be true
    end

    it 'returns false for unknown setting' do
      expect(described_class.valid_field?('unknown', 'field')).to be false
    end
  end

  describe '.generate_secrets' do
    it 'generates all secrets' do
      secrets = described_class.generate_secrets
      expect(secrets.keys).to match_array(described_class::SYSTEM_SECRETS.keys)
      expect(secrets.values).to all(be_present)
    end

    it 'generates unique values on each call' do
      secrets1 = described_class.generate_secrets
      secrets2 = described_class.generate_secrets
      expect(secrets1['postgres_password']).not_to eq(secrets2['postgres_password'])
    end
  end

  describe '.missing_secrets' do
    it 'returns all secrets when system data is empty' do
      missing = described_class.missing_secrets({})
      expect(missing.keys).to match_array(described_class::SYSTEM_SECRETS.keys)
    end

    it 'returns only missing secrets' do
      existing = { 'postgres_password' => 'exists', 'influx_org' => 'org' }
      missing = described_class.missing_secrets(existing)
      expect(missing.keys).not_to include('postgres_password', 'influx_org')
      expect(missing.keys).to include('secret_key_base', 'influx_password')
    end

    it 'returns empty hash when all secrets present' do
      all_present = described_class::SYSTEM_SECRETS.transform_values { 'present' }
      missing = described_class.missing_secrets(all_present)
      expect(missing).to be_empty
    end
  end

  describe 'consistency with surveys' do
    survey_settings = Configuration::ALL.reject { |s| s == 'sensors' }
    survey_settings.select { |s| Rails.root.join("config/surveys/#{s}.json").exist? }.each do |setting|
      it "#{setting}.json fields are all in described_class" do
        survey = JSON.parse(Rails.root.join("config/surveys/#{setting}.json").read)
        survey_fields = extract_survey_field_names(survey)

        schema_fields = described_class.fields_for(setting)
        next if schema_fields == :dynamic

        survey_fields.each do |field|
          expect(schema_fields).to include(field),
                                   "Survey field '#{field}' from #{setting}.json " \
                                   "is not in ConfigSchema::FIELDS['#{setting}']"
        end
      end
    end
  end

  # Extract all question "name" values from a SurveyJS JSON
  def extract_survey_field_names(survey)
    names = []
    survey['pages']&.each do |page|
      page['elements']&.each do |element|
        name = element['name']
        # Skip non-data elements (comments, info panels)
        next if element['type'] == 'comment'
        next if element['readOnly'] == true

        names << name if name
      end
    end
    names
  end
end
