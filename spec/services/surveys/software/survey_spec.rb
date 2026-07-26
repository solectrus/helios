RSpec.describe Surveys::Software::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    let(:matrix) { find_survey_element(result, 'service_channels') }

    it 'renders a matrix with stable/develop as columns' do
      expect(matrix).to include('type' => 'matrix')
      expect(matrix['columns'].pluck('value')).to eq(%w[latest develop])
    end

    it 'lists the dashboard and HELIOS rows in full mode' do
      expect(matrix['rows'].pluck('value')).to eq(%w[dashboard helios])
    end

    it 'defaults every row to the stable channel' do
      expect(matrix['defaultValue']).to eq('dashboard' => 'latest', 'helios' => 'latest')
    end

    it 'offers interval and fixed-time checking, defaulting to the interval' do
      expect(find_survey_element(result, 'update_mode')).to include(
        'type' => 'radiogroup',
        'defaultValue' => ConfigSchema::UPDATE_MODE_INTERVAL,
      )
      expect(find_survey_element(result, 'update_mode')['choices'].pluck('value'))
        .to eq(ConfigSchema::UPDATE_MODES)
    end

    # The setting used to be gated on a service running the develop channel;
    # it applies to every channel now (Issue #350).
    it 'asks for the update mode regardless of the chosen channels' do
      expect(find_survey_element(result, 'update_mode')).not_to have_key('visibleIf')
    end

    it 'keeps the update-interval radiogroup with daily as the default' do
      expect(find_survey_element(result, 'update_interval')).to include(
        'type' => 'radiogroup',
        'defaultValue' => ConfigSchema::DEFAULT_UPDATE_INTERVAL,
        'visibleIf' => "{update_mode} = '#{ConfigSchema::UPDATE_MODE_INTERVAL}'",
      )
    end

    it 'offers a time picker for the fixed-time mode' do
      expect(find_survey_element(result, 'update_time')).to include(
        'inputType' => 'time',
        'defaultValue' => ConfigSchema::DEFAULT_UPDATE_TIME,
        'visibleIf' => "{update_mode} = '#{ConfigSchema::UPDATE_MODE_TIME}'",
      )
    end

    it 'pulls in a collector once its source is active' do
      with_config_yaml(
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
        'senec' => { 'version' => '4' },
      )

      expect(matrix['rows'].pluck('value')).to include('senec_collector')
    end

    it 'pulls in the tibber-collector once a Tibber token is configured' do
      with_config_yaml('tibber' => { 'token' => 'secret-token' })

      expect(matrix['rows'].pluck('value')).to include('tibber_collector')
    end

    it 'omits the tibber-collector without a Tibber token' do
      expect(matrix['rows'].pluck('value')).not_to include('tibber_collector')
    end

    it 'keeps the tibber-collector in dashboard_only mode, where it still runs' do
      with_config_yaml('deployment' => { 'mode' => 'dashboard_only' },
                       'tibber' => { 'token' => 'secret-token' })

      expect(matrix['rows'].pluck('value')).to include('tibber_collector')
    end

    it 'pulls in the senec-charger once it is enabled with all preconditions' do
      with_config_yaml(
        'senec' => { 'adapter' => 'local' },
        'tibber' => { 'token' => 'secret-token' },
        'forecast' => { 'forecast' => 'forecast.solar' },
        'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
        'senec_charger' => { 'interval' => '3600' },
      )

      expect(matrix['rows'].pluck('value')).to include('senec_charger')
    end

    it 'omits the senec-charger when its preconditions are unmet' do
      with_config_yaml('senec_charger' => { 'interval' => '3600' })

      expect(matrix['rows'].pluck('value')).not_to include('senec_charger')
    end

    it 'pulls in ingest when a balcony sensor activates it' do
      with_config_yaml(
        'sensors' => { 'inverter_power_2' => { 'source' => 'shelly', 'is_balcony' => true } },
      )

      expect(matrix['rows'].pluck('value')).to include('ingest')
    end

    it 'pulls in power-splitter once a second consumer joins the mandatory sensors' do
      with_config_yaml(
        'sensors' => {
          'grid_import_power' => { 'source' => 'senec' },
          'house_power' => { 'source' => 'senec' },
          'wallbox_power' => { 'source' => 'senec' },
        },
      )

      expect(matrix['rows'].pluck('value')).to include('power_splitter')
    end

    it 'omits power-splitter when only the mandatory sensors are mapped' do
      with_config_yaml(
        'sensors' => {
          'grid_import_power' => { 'source' => 'senec' },
          'house_power' => { 'source' => 'senec' },
        },
      )

      expect(matrix['rows'].pluck('value')).not_to include('power_splitter')
    end

    it 'always offers the HELIOS row, even in collectors_only mode without sources' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      expect(matrix['rows'].pluck('value')).to eq(%w[helios])
    end
  end
end
