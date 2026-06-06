RSpec.describe Surveys::Tibber::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    # A local battery plus a running forecast collector are what the charging
    # half needs; both live outside the charger's own section.
    def with_charging_preconditions
      with_config_yaml(
        'senec' => { 'adapter' => 'local' },
        'forecast' => { 'forecast' => 'forecast.solar' },
        'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
      )
    end

    def page_named(survey, name)
      survey['pages'].find { |page| page['name'] == name }
    end

    before { with_charging_preconditions }

    it 'puts the prices toggle on the first page, next to what the dashboard does with them' do
      page = page_named(result, 'p_enable')
      expect(page['elements'].pluck('name')).to eq(%w[enabled dashboard_info])
      expect(page['elements'].first).to include('type' => 'boolean', 'defaultValue' => false)
    end

    it 'says up front that the dashboard does not bill by these prices yet' do
      expect(find_survey_element(result, 'dashboard_info')['html']['de'])
        .to include('rechnet damit noch nicht')
    end

    it 'gates the Tibber pages on the prices being collected and clears them otherwise' do
      expect(result['clearInvisibleValues']).to eq('onHidden')
      expect(page_named(result, 'p_token')['visibleIf']).to eq('{enabled} = true')
      expect(page_named(result, 'p_charging')['visibleIf']).to eq('{enabled} = true')
    end

    it 'gates the charger tuning on charging being switched on as well' do
      %w[p_price p_forecast p_options].each do |name|
        expect(page_named(result, name)['visibleIf']).to eq('{enabled} = true and {charging} = true')
      end
    end

    it 'asks for the Tibber credentials the collector needs' do
      expect(page_named(result, 'p_token')['elements'].pluck('name'))
        .to eq(%w[token_link token measurement])
      expect(find_survey_element(result, 'measurement')).to include('defaultValue' => 'Prices')
    end

    it 'spells out the trade-offs once charging is switched on' do
      expect(page_named(result, 'p_charging')['elements'].pluck('name')).to eq(%w[charging risk_info])
      expect(find_survey_element(result, 'risk_info')['visibleIf']).to eq('{charging} = true')
    end

    it 'groups the price decision on its own page' do
      expect(page_named(result, 'p_price')['elements'].pluck('name')).to eq(%w[price_max price_time_range])
    end

    it 'keeps the optional and technical knobs on the last page' do
      expect(page_named(result, 'p_options')['elements'].pluck('name')).to eq(%w[interval dry_run])
    end

    it 'defaults the tuning fields to the collector defaults' do
      expect(find_survey_element(result, 'interval')).to include('defaultValue' => '3600', 'min' => 60)
      expect(find_survey_element(result, 'price_max')).to include('defaultValue' => '70', 'min' => 1, 'max' => 99)
      expect(find_survey_element(result, 'price_time_range')).to include('defaultValue' => '4')
      expect(find_survey_element(result, 'forecast_threshold')).to include('defaultValue' => '20')
      expect(find_survey_element(result, 'dry_run')).to include('type' => 'boolean', 'defaultValue' => false)
    end

    it 'drops the unavailable hint while charging is on offer' do
      expect(page_named(result, 'p_charging_unavailable')).to be_nil
    end

    context 'with a local battery but no forecast collector' do
      before { with_config_yaml('senec' => { 'adapter' => 'local' }) }

      it 'names the missing forecast instead of offering the charging questions' do
        expect(result['pages'].pluck('name')).to eq(%w[p_enable p_token p_charging_unavailable])
      end
    end

    context 'without a locally-queried SENEC battery' do
      it 'asks for the prices alone with a cloud battery' do
        with_config_yaml('senec' => { 'adapter' => 'cloud' })
        expect(result['pages'].pluck('name')).to eq(%w[p_enable p_token])
      end

      it 'asks for the prices alone without any battery' do
        with_config_yaml
        expect(result['pages'].pluck('name')).to eq(%w[p_enable p_token])
      end

      it 'asks for the prices alone in collectors_only mode, local battery or not' do
        with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
                         'senec' => { 'adapter' => 'local' })
        expect(result['pages'].pluck('name')).to eq(%w[p_enable p_token])
      end
    end
  end
end
