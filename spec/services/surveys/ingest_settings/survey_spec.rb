RSpec.describe Surveys::IngestSettings::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'exposes the retention_hours element with a sensible default' do
      expect(find_survey_element(result, 'retention_hours')).to include(
        'defaultValue' => '12',
        'inputType' => 'number',
      )
    end

    it 'offers the recalculation switch, on by default' do
      expect(find_survey_element(result, 'active')).to include(
        'type' => 'boolean',
        'defaultValue' => true,
      )
    end

    describe 'the write address' do
      subject(:html) { find_survey_element(result, 'ingest_endpoint')['html'] }

      def with_balcony(data = {})
        with_config_yaml(
          data.deep_merge(
            'sensors' => { 'inverter_power_2' => { 'source' => 'shelly', 'is_balcony' => true } },
          ),
        )
      end

      # A balcony power plant HELIOS cannot reroute itself: the one case in
      # which the endpoint has an addressee.
      def with_external_balcony
        with_config_yaml(
          'system' => { 'app_host' => 'solectrus.fritz.box' },
          'sensors' => {
            'inverter_power_4' => { 'source' => 'external', 'is_balcony' => true },
          },
        )
      end

      it 'names the address every source writes to' do
        with_balcony('system' => { 'app_host' => 'solectrus.fritz.box' })

        expect(html['de']).to include('http://solectrus.fritz.box:4567')
      end

      # A switched-off recalculation runs no service, so no address exists.
      # The condition travels with the element so the switch hides it at once,
      # rather than only on the next render.
      it 'follows the switch without a reload' do
        with_balcony('ingest' => { 'active' => false })

        expect(find_survey_element(result, 'ingest_endpoint')).to include(
          'visibleIf' => '{active} = true',
        )
      end

      it 'is left out while no balcony power plant offers Ingest' do
        with_config_yaml('sensors' => { 'inverter_power_2' => { 'source' => 'shelly' } })

        expect(find_survey_element(result, 'ingest_endpoint')).to be_nil
      end

      it 'lists the values an external source still has to redirect' do
        with_external_balcony

        expect(html['default']).to include(I18n.t('sensors.inverter_power_4', locale: :en))
      end

      # The address is the only thing that changes, so the hint says so: Ingest
      # speaks the InfluxDB write API, and a source that keeps its credentials
      # needs no further answer before it is redirected.
      it 'says the credentials of such a source stay as they are' do
        with_external_balcony

        expect(html['default']).to include('Token and bucket stay the same')
      end

      it 'names the port alone while no address is configured' do
        with_balcony

        expect(html['de']).to include("<code>#{Export::IngestEndpoint::PORT}</code>")
        expect(html['de']).not_to include('http')
      end

      it 'says nothing is left to do while every collector is managed' do
        with_balcony('system' => { 'app_host' => 'solectrus.fritz.box' })

        expect(html['default']).to include('writes there already')
      end
    end
  end
end
