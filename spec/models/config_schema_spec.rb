RSpec.describe ConfigSchema do
  describe '.fields_for' do
    it 'returns fields for system' do
      fields = described_class.fields_for('system')
      expect(fields).to include(
        'timezone', 'installation_date',
        'app_host', 'admin_password', 'secret_key_base'
      )
    end

    it 'returns fields for dashboard' do
      fields = described_class.fields_for('dashboard')
      expect(fields).to include('image')
    end

    it 'returns fields for postgresql' do
      fields = described_class.fields_for('postgresql')
      expect(fields).to include('image', 'password')
    end

    it 'returns fields for influxdb' do
      fields = described_class.fields_for('influxdb')
      expect(fields).to include(
        'image', 'org', 'bucket', 'password',
        'token_admin', 'token_readwrite', 'token_write', 'token_read'
      )
    end

    it 'returns fields for backup' do
      fields = described_class.fields_for('backup')
      expect(fields).to include('aws_access_key_id', 'aws_bucket')
    end

    it 'returns fields for redis' do
      fields = described_class.fields_for('redis')
      expect(fields).to include('image')
    end

    it 'returns fields for helios (image channel)' do
      expect(described_class.fields_for('helios')).to include('image')
    end

    it 'returns fields for watchtower' do
      fields = described_class.fields_for('watchtower')
      expect(fields).to include('image')
    end

    it 'returns fields for senec' do
      fields = described_class.fields_for('senec')
      expect(fields).to include('host', 'schema', 'interval', 'adapter')
    end

    it 'returns fields for mqtt' do
      fields = described_class.fields_for('mqtt')
      expect(fields).to include('mqtt_host', 'mqtt_port')
    end

    it 'returns fields for shelly' do
      fields = described_class.fields_for('shelly')
      expect(fields).to include('connection', 'interval')
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

    it 'returns true for admin_password in system' do
      expect(described_class.valid_field?('system', 'admin_password')).to be true
    end

    it 'returns true for secret_key_base in system' do
      expect(described_class.valid_field?('system', 'secret_key_base')).to be true
    end

    it 'returns true for image in dashboard' do
      expect(described_class.valid_field?('dashboard', 'image')).to be true
    end

    it 'returns true for image in postgresql' do
      expect(described_class.valid_field?('postgresql', 'image')).to be true
    end

    it 'returns false for unknown system field' do
      expect(described_class.valid_field?('system', 'nonsense')).to be false
    end

    it 'returns true for postgresql fields' do
      expect(described_class.valid_field?('postgresql', 'password')).to be true
    end

    it 'returns true for influxdb fields' do
      expect(described_class.valid_field?('influxdb', 'token_admin')).to be true
    end

    it 'returns true for known senec fields' do
      expect(described_class.valid_field?('senec', 'host')).to be true
    end

    it 'returns false for unknown senec field' do
      expect(described_class.valid_field?('senec', 'nonsense')).to be false
    end

    it 'returns true for any sensor field (dynamic)' do
      expect(described_class.valid_field?('sensors', 'anything')).to be true
    end

    it 'returns false for unknown setting' do
      expect(described_class.valid_field?('unknown', 'field')).to be false
    end
  end

  describe '.missing_auto_generated' do
    before { with_config_yaml }

    it 'returns all sections with defaults when configuration is empty' do
      config = Configuration.current
      missing = described_class.missing_auto_generated(config)

      expect(missing.keys).to match_array(%w[system dashboard postgresql influxdb redis watchtower ingest helios])
    end

    it 'returns all system defaults when empty' do
      missing = described_class.missing_auto_generated(Configuration.current)
      expect(missing['system'].keys).to match_array(%w[secret_key_base admin_password])
    end

    it 'returns all postgresql defaults when empty' do
      missing = described_class.missing_auto_generated(Configuration.current)
      expect(missing['postgresql'].keys).to match_array(%w[image password])
    end

    it 'returns all influxdb defaults when empty' do
      missing = described_class.missing_auto_generated(Configuration.current)
      expect(missing['influxdb'].keys).to match_array(
        %w[image org bucket password token_admin token_readwrite token_write token_read],
      )
    end

    it 'returns image defaults for image-only sections when empty' do
      missing = described_class.missing_auto_generated(Configuration.current)

      %w[dashboard redis watchtower].each do |section|
        expect(missing[section].keys).to match_array(%w[image])
      end
    end

    it 'returns only missing defaults' do
      config = Configuration.current
      config.update('system', { 'admin_password' => 'set' })
      config.update('postgresql', { 'password' => 'exists' })
      config.update('influxdb', { 'org' => 'myorg' })

      missing = described_class.missing_auto_generated(config)

      expect(missing['system'].keys).to include('secret_key_base')
      expect(missing['system'].keys).not_to include('admin_password')
      expect(missing['postgresql'].keys).not_to include('password')
      expect(missing['influxdb'].keys).not_to include('org')
      expect(missing['influxdb'].keys).to include('password')
    end

    it 'returns empty hash when all values present' do
      config = Configuration.current
      # Populate all auto-generated defaults. Resolve sequentially so a
      # 1-arity lambda (admin_password ← secret_key_base) sees its dependency
      # filled in by the same loop.
      ConfigSchema::AUTO_GENERATED.each do |section, defaults|
        resolved = {}
        defaults.each do |key, default|
          resolved[key] = described_class.resolve_default(default, resolved)
        end
        config.update(section, resolved)
      end

      missing = described_class.missing_auto_generated(config)
      expect(missing).to be_empty
    end
  end

  describe 'consistency with surveys' do
    survey_settings = (Configuration::ALL - Configuration::HIDDEN - Configuration::READ_ONLY_SETTINGS)
    survey_settings.select { |s| Rails.root.join("app/services/surveys/#{s}/survey.json").exist? }.each do |setting|
      next if setting == 'software' # custom channel-token persistence, not a simple field map

      it "#{setting}/survey.json fields are all in described_class" do
        survey = JSON.parse(Rails.root.join("app/services/surveys/#{setting}/survey.json").read)
        survey_fields = extract_survey_field_names(survey)

        # Mini-surveys validate against their parent singleton's schema —
        # they own a slice of the singleton, not a section of their own.
        # Borrowed fields (BORROWED_FIELDS) are validated against the foreign
        # section that actually stores them.
        parent = Configuration::SETTING_GROUPS.dig(setting, :singleton) || setting
        borrowed = Configuration::BORROWED_FIELDS.fetch(setting, {})

        # UI-only toggles that drive visibility but are not persisted: the
        # boolean `enabled` flag, reverse_proxy's tri-state `mode` selector
        # (re-derived from app_domain/bind_ip on load, see SettingsController),
        # and system_general's `currency_preset` dropdown (drives the `currency`
        # freetext field, only `currency` is stored).
        ui_only =
          case setting
          when 'reverse_proxy' then %w[enabled mode]
          when 'system_general' then %w[enabled currency_preset]
          else %w[enabled]
          end

        survey_fields.reject { |f| ui_only.include?(f) }.each do |field|
          section = borrowed[field] || parent
          schema_fields = described_class.fields_for(section)
          next if schema_fields == :dynamic

          expect(schema_fields).to include(field),
                                   "Survey field '#{field}' from #{setting}.json " \
                                   "is not in ConfigSchema::FIELDS['#{section}']"
        end
      end
    end
  end

  # Extract all question "name" values from a SurveyJS JSON
  def extract_survey_field_names(survey)
    names = []
    survey['pages']&.each { |page| collect_question_names(page['elements'], names) }
    names
  end

  def collect_question_names(elements, names)
    elements&.each do |element|
      # Skip non-data elements (comments, info text)
      next if %w[comment html].include?(element['type'])
      next if element['readOnly'] == true

      # Panels are layout containers; recurse into their nested elements
      if element['type'] == 'panel'
        collect_question_names(element['elements'], names)
      elsif element['name']
        names << element['name']
      end
    end
  end
end
