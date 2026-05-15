RSpec.describe Surveys::Software::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    let(:matrix) { find_survey_element(result, 'service_channels') }

    it 'renders a matrix with stable/develop as columns' do
      expect(matrix).to include('type' => 'matrix')
      expect(matrix['columns'].pluck('value')).to eq(%w[latest develop])
    end

    it 'lists the dashboard row in full mode' do
      expect(matrix['rows'].pluck('value')).to eq(%w[dashboard])
    end

    it 'defaults every row to the stable channel' do
      expect(matrix['defaultValue']).to eq('dashboard' => 'latest')
    end

    it 'keeps the update-interval radiogroup with daily as the default' do
      expect(find_survey_element(result, 'update_interval')).to include(
        'type' => 'radiogroup',
        'defaultValue' => '86400',
      )
    end

    it 'shows the update interval only when a service runs on develop' do
      expect(find_survey_element(result, 'update_interval')).to include(
        'visibleIf' => "anyValueEquals({service_channels}, 'develop') = true",
        'resetValueIf' => "anyValueEquals({service_channels}, 'develop') = false",
        'clearIfInvisible' => 'none',
      )
    end

    it 'pulls in a collector once its source is active' do
      with_config_yaml(
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
        'senec' => { 'version' => '4' },
      )

      expect(matrix['rows'].pluck('value')).to include('senec_collector')
    end

    it 'pulls in ingest when a balcony sensor activates it' do
      with_config_yaml(
        'sensors' => { 'inverter_power_2' => { 'source' => 'shelly', 'is_balcony' => true } },
      )

      expect(matrix['rows'].pluck('value')).to include('ingest')
    end

    it 'pulls in power-splitter once its mandatory sensors are mapped' do
      with_config_yaml(
        'sensors' => {
          'grid_import_power' => { 'source' => 'senec' },
          'house_power' => { 'source' => 'senec' },
        },
      )

      expect(matrix['rows'].pluck('value')).to include('power_splitter')
    end

    it 'omits the matrix entirely when no service is active (collectors_only without sources)' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      expect(find_survey_element(result, 'service_channels')).to be_nil
    end
  end
end
